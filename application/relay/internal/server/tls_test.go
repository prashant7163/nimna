// Session 6 TLS tests (architecture note §25): the wss:// smoke path,
// /healthz (§26), the state-independence covering test for TLS-layer
// probes (the §5.1 carve-out class), and the certificate reloader.
package server

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"io"
	"log/slog"
	"math/big"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nimna.app/relay/internal/wire"
)

// writeTestCertPair generates a self-signed ECDSA P-256 certificate for
// 127.0.0.1 AT TEST RUNTIME (no key-shaped file is ever committed) and
// writes cert/key PEMs under dir with the given boring basenames.
func writeTestCertPair(t *testing.T, dir, certName, keyName string, notAfter time.Time) (certPath, keyPath string) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	tmpl := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "nimna-relay-test"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              notAfter,
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		IPAddresses:           []net.IP{net.ParseIP("127.0.0.1")},
		IsCA:                  true, // self-signed leaf usable as its own root
		BasicConstraintsValid: true,
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatalf("create certificate: %v", err)
	}
	keyDER, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatalf("marshal key: %v", err)
	}
	certPath = filepath.Join(dir, certName)
	keyPath = filepath.Join(dir, keyName)
	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: keyDER})
	if err := os.WriteFile(certPath, certPEM, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(keyPath, keyPEM, 0o600); err != nil {
		t.Fatal(err)
	}
	return certPath, keyPath
}

// poolFor loads the cert into a fresh root pool (the testclient -tls-ca
// mechanism, in-process).
func poolFor(t *testing.T, certPath string) *x509.CertPool {
	t.Helper()
	pemBytes, err := os.ReadFile(certPath)
	if err != nil {
		t.Fatal(err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(pemBytes) {
		t.Fatal("no certs in pool PEM")
	}
	return pool
}

// dialTLS is dial() over wss with a custom root pool.
func dialTLS(t *testing.T, url string, pool *x509.CertPool) *wsClient {
	t.Helper()
	hc := &http.Client{Transport: &http.Transport{
		TLSClientConfig: &tls.Config{RootCAs: pool},
	}}
	ctx, cancel := context.WithTimeout(context.Background(), recvTimeout)
	defer cancel()
	ws, _, err := websocket.Dial(ctx, url, &websocket.DialOptions{HTTPClient: hc})
	if err != nil {
		t.Fatalf("wss dial: %v", err)
	}
	ws.SetReadLimit(-1)
	c := &wsClient{t: t, ws: ws, frames: make(chan []byte, 16), closed: make(chan struct{})}
	go func() {
		defer close(c.closed)
		for {
			_, data, err := ws.Read(context.Background())
			if err != nil {
				c.readErr = err
				return
			}
			c.frames <- data
		}
	}()
	t.Cleanup(func() { _ = ws.CloseNow() })
	return c
}

// TestServeTLSBridgesOverWSS: the full listener chain — raw TCP → limit
// listener → tls.NewListener → HTTP (§17 ordering) — carries a real
// rendezvous bridge and verbatim PAIR_DATA over wss://.
func TestServeTLSBridgesOverWSS(t *testing.T) {
	certPath, keyPath := writeTestCertPair(t, t.TempDir(), "cert.pem", "key.pem",
		time.Now().Add(24*time.Hour))
	url, _ := newRelayServe(t, Config{TLSCert: certPath, TLSKey: keyPath})
	wssURL := "wss://" + strings.TrimPrefix(url, "ws://")
	pool := poolFor(t, certPath)

	a := dialTLS(t, wssURL, pool)
	b := dialTLS(t, wssURL, pool)
	topic := [16]byte{0xAB, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}
	a.send(wire.Encode(wire.RegisterTopic, topic, nil))
	b.send(wire.Encode(wire.RegisterTopic, topic, nil))
	bridged := wire.Encode(wire.TopicBridged, topic, nil)
	if got := a.expectFrame(); !bytes.Equal(got, bridged) {
		t.Fatalf("a: got % x, want TOPIC_BRIDGED", got)
	}
	if got := b.expectFrame(); !bytes.Equal(got, bridged) {
		t.Fatalf("b: got % x, want TOPIC_BRIDGED", got)
	}
	pd := wire.Encode(wire.PairData, topic, []byte("ciphertext over tls"))
	a.send(pd)
	if got := b.expectFrame(); !bytes.Equal(got, pd) {
		t.Fatalf("PAIR_DATA not verbatim over wss: % x", got)
	}
}

// TestHealthz: GET /healthz on the ops listener answers the pinned §26
// body; every other method/path combination still 404s; /metrics stays.
func TestHealthz(t *testing.T) {
	s := New(Config{MetricsAddr: "127.0.0.1:0", Version: "test-1.2.3"}, nil)
	ln, err := newLocalListener()
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- s.Serve(ctx, ln) }()
	t.Cleanup(func() {
		cancel()
		select {
		case <-done:
		case <-time.After(recvTimeout):
			t.Error("Serve did not stop")
		}
	})
	var ops string
	for i := 0; i < deadTopicPolls && ops == ""; i++ {
		ops = s.OpsAddr()
		time.Sleep(10 * time.Millisecond)
	}
	if ops == "" {
		t.Fatal("ops listener never bound")
	}

	resp, err := http.Get("http://" + ops + "/healthz")
	if err != nil {
		t.Fatalf("GET /healthz: %v", err)
	}
	body, _ := io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("/healthz status: %d", resp.StatusCode)
	}
	if got, want := string(body), "ok nimna-relay test-1.2.3\n"; got != want {
		t.Fatalf("/healthz body: %q, want %q", got, want)
	}
	if ct := resp.Header.Get("Content-Type"); !strings.HasPrefix(ct, "text/plain") {
		t.Fatalf("/healthz content-type: %q", ct)
	}

	// Everything else still 404s; /metrics still serves.
	for _, probe := range []struct{ method, path string }{
		{http.MethodPost, "/healthz"},
		{http.MethodGet, "/health"},
		{http.MethodGet, "/"},
	} {
		req, _ := http.NewRequest(probe.method, "http://"+ops+probe.path, nil)
		r, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatalf("%s %s: %v", probe.method, probe.path, err)
		}
		_ = r.Body.Close()
		if r.StatusCode != http.StatusNotFound {
			t.Errorf("%s %s: status %d, want 404", probe.method, probe.path, r.StatusCode)
		}
	}
	r, err := http.Get("http://" + ops + "/metrics")
	if err != nil {
		t.Fatalf("GET /metrics: %v", err)
	}
	_ = r.Body.Close()
	if r.StatusCode != http.StatusOK {
		t.Errorf("/metrics status: %d", r.StatusCode)
	}
}

// tlsProbe writes raw or handshake bytes at the TLS port and returns
// every byte the relay sent back before closing — the observable surface
// of a failed handshake.
func tlsProbe(t *testing.T, addr string, probe func(c net.Conn)) []byte {
	t.Helper()
	raw, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatalf("probe dial: %v", err)
	}
	defer raw.Close()
	_ = raw.SetDeadline(time.Now().Add(recvTimeout))
	rec := &recordingConn{Conn: raw}
	probe(rec)
	// Drain whatever remains until close/deadline.
	_, _ = io.Copy(io.Discard, rec)
	return rec.received.Bytes()
}

// recordingConn captures everything read from the wire.
type recordingConn struct {
	net.Conn
	received bytes.Buffer
}

func (c *recordingConn) Read(b []byte) (int, error) {
	n, err := c.Conn.Read(b)
	c.received.Write(b[:n])
	return n, err
}

// TestTLSFailuresAreStateIndependent is §25's covering test: TLS-layer
// probes — plain HTTP bytes to the TLS port, a 1.2-only ClientHello, an
// h2-only ALPN offer — produce byte-identical behavior against an empty
// relay and one holding registered topics, a bridge, and a pending
// knock. Handshake alerts are stdlib-emitted below the Nimna frame, a
// pure function of the offending transport bytes + the RFC + the
// configured certificate; no Nimna protocol state can reach them (the
// §5.1 carve-out class).
func TestTLSFailuresAreStateIndependent(t *testing.T) {
	// ONE certificate serves both relays: the probe surface must differ
	// only in relay state.
	certPath, keyPath := writeTestCertPair(t, t.TempDir(), "cert.pem", "key.pem",
		time.Now().Add(24*time.Hour))
	pool := poolFor(t, certPath)
	cfg := Config{TLSCert: certPath, TLSKey: keyPath}

	urlEmpty, _ := newRelayServe(t, cfg)
	urlLoaded, _ := newRelayServe(t, cfg)
	addrEmpty := strings.TrimPrefix(urlEmpty, "ws://")
	addrLoaded := strings.TrimPrefix(urlLoaded, "ws://")

	// Load the second relay: bridged topic, registered CRID, pending
	// knock — the states a probe must not be able to distinguish.
	wssLoaded := "wss://" + addrLoaded
	a := dialTLS(t, wssLoaded, pool)
	b := dialTLS(t, wssLoaded, pool)
	topic := [16]byte{0xEE, 1, 2, 3}
	crid := [16]byte{0xDD, 9, 8, 7}
	a.send(wire.Encode(wire.RegisterTopic, topic, nil))
	b.send(wire.Encode(wire.RegisterTopic, topic, nil))
	a.expectFrame() // TOPIC_BRIDGED
	b.expectFrame()
	a.send(wire.Encode(wire.RegisterCRID, crid, nil))
	b.send(wire.Encode(wire.RegisterCRID, crid, nil))
	a.send(wire.Encode(wire.Knock, crid, nil))
	b.expectFrame() // KNOCK_FWD — pending knock now held

	probes := map[string]func(c net.Conn){
		"plain HTTP to the TLS port": func(c net.Conn) {
			_, _ = c.Write([]byte("GET / HTTP/1.1\r\nHost: relay\r\n\r\n"))
		},
		"1.2-only ClientHello": func(c net.Conn) {
			tc := tls.Client(c, &tls.Config{
				RootCAs:    pool,
				MaxVersion: tls.VersionTLS12,
				ServerName: "127.0.0.1",
			})
			_ = tc.Handshake() // must fail: the relay floors at 1.3
		},
		"h2-only ALPN offer": func(c net.Conn) {
			tc := tls.Client(c, &tls.Config{
				RootCAs:    pool,
				NextProtos: []string{"h2"},
				ServerName: "127.0.0.1",
			})
			_ = tc.Handshake() // must fail: the public port is http/1.1-only
		},
	}
	for name, probe := range probes {
		t.Run(name, func(t *testing.T) {
			gotEmpty := tlsProbe(t, addrEmpty, probe)
			gotLoaded := tlsProbe(t, addrLoaded, probe)
			if !bytes.Equal(gotEmpty, gotLoaded) {
				t.Errorf("probe response differs between empty and loaded relay:\nempty:  % x\nloaded: % x",
					gotEmpty, gotLoaded)
			}
			// And no identifier bytes appear in whatever came back.
			for id, raw := range map[string][]byte{"topic": topic[:], "crid": crid[:]} {
				if bytes.Contains(gotLoaded, raw) {
					t.Errorf("probe response contains %s bytes", id)
				}
			}
		})
	}
}

// TestCertReloader: initial load, throttled mtime-checked reload with the
// fixed identifier-free log lines, keep-old-cert on failure, boot-fatal
// initial load (all §25 pins; injectable clock and throttle).
func TestCertReloader(t *testing.T) {
	dir := t.TempDir()
	notAfter1 := time.Date(2027, 1, 1, 0, 0, 0, 0, time.UTC)
	notAfter2 := time.Date(2027, 6, 1, 0, 0, 0, 0, time.UTC)
	certPath, keyPath := writeTestCertPair(t, dir, "cert.pem", "key.pem", notAfter1)
	cert2Path, key2Path := writeTestCertPair(t, dir, "cert2.pem", "key2.pem", notAfter2)

	clock := time.Date(2026, 7, 4, 12, 0, 0, 0, time.UTC)
	now := func() time.Time { return clock }
	logBuf := &lockedBuf{}
	logger := slog.New(slog.NewTextHandler(logBuf, nil))
	const throttle = time.Minute

	r, err := newCertReloader(certPath, keyPath, logger, now, throttle)
	if err != nil {
		t.Fatalf("newCertReloader: %v", err)
	}
	got, err := r.GetCertificate(nil)
	if err != nil || got == nil {
		t.Fatalf("GetCertificate: %v, %v", got, err)
	}
	if leafNotAfter(got) != notAfter1 {
		t.Fatalf("initial leaf notAfter: %v, want %v", leafNotAfter(got), notAfter1)
	}

	// Swap the pair (certbot deploy hook shape: key first, then cert)
	// with an explicit future mtime; inside the throttle window nothing
	// reloads, past it the handshake-driven check picks it up.
	copyFile(t, key2Path, keyPath)
	copyFile(t, cert2Path, certPath)
	newMtime := time.Now().Add(time.Hour)
	if err := os.Chtimes(certPath, newMtime, newMtime); err != nil {
		t.Fatal(err)
	}
	if got, _ = r.GetCertificate(nil); leafNotAfter(got) != notAfter1 {
		t.Fatal("reloaded inside the stat-throttle window")
	}
	clock = clock.Add(throttle + time.Second)
	if got, _ = r.GetCertificate(nil); leafNotAfter(got) != notAfter2 {
		t.Fatalf("renewed certificate not picked up: leaf notAfter %v", leafNotAfter(got))
	}
	out := logBuf.String()
	if !strings.Contains(out, "tls certificate reloaded") ||
		!strings.Contains(out, notAfter2.Format(time.RFC3339)) {
		t.Errorf("reload success line missing or without notAfter: %q", out)
	}
	// The log carries cert METADATA only — never contents (no PEM, no
	// long hex runs).
	if strings.Contains(out, "BEGIN") || regexp.MustCompile(`[0-9a-fA-F]{32,}`).MatchString(out) {
		t.Errorf("reload log carries certificate material: %q", out)
	}

	// Reload failure: garbage cert file, newer mtime — the old cert
	// keeps serving and one fixed Warn line fires.
	if err := os.WriteFile(certPath, []byte("garbage, not a certificate"), 0o600); err != nil {
		t.Fatal(err)
	}
	badMtime := newMtime.Add(time.Hour)
	if err := os.Chtimes(certPath, badMtime, badMtime); err != nil {
		t.Fatal(err)
	}
	clock = clock.Add(throttle + time.Second)
	if got, _ = r.GetCertificate(nil); leafNotAfter(got) != notAfter2 {
		t.Fatal("a failed reload must keep serving the previous certificate")
	}
	if !strings.Contains(logBuf.String(), "tls certificate reload failed") {
		t.Errorf("reload failure Warn line missing: %q", logBuf.String())
	}

	// Boot-fatal initial load: missing pair.
	if _, err := newCertReloader(filepath.Join(dir, "nope.pem"), filepath.Join(dir, "nope.key"),
		logger, now, throttle); err == nil {
		t.Fatal("newCertReloader must fail on an unloadable initial pair")
	}
}

// TestRunTLSBootFatalPrecedesBind: an unloadable certificate pair fails
// Run BEFORE the public port is bound — under systemd Restart=always a
// boot-fatal config error must never flap bind/unbind. Proven by pairing
// the bad cert with an unbindable address: the TLS load error wins, so
// the bind was never attempted.
func TestRunTLSBootFatalPrecedesBind(t *testing.T) {
	dir := t.TempDir()
	s := New(Config{
		Addr:    "203.0.113.1:1", // TEST-NET-3: locally unbindable
		TLSCert: filepath.Join(dir, "missing.pem"),
		TLSKey:  filepath.Join(dir, "missing.key"),
	}, nil)
	err := s.Run(context.Background())
	if err == nil {
		t.Fatal("Run must fail on an unloadable TLS pair")
	}
	if !strings.HasPrefix(err.Error(), "tls: ") {
		t.Fatalf("want the pre-bind TLS load error, got: %v", err)
	}
}

func copyFile(t *testing.T, src, dst string) {
	t.Helper()
	b, err := os.ReadFile(src)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(dst, b, 0o600); err != nil {
		t.Fatal(err)
	}
}
