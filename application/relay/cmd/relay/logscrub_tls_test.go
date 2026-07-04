// Session 6 extension of the §20 log-scrub assertion (architecture note
// §25): the real binary booted WITH TLS, real flows over wss://, and
// clients that fail their handshakes on purpose — asserting the client
// IP and every known identifier still never appear, that per-handshake
// errors are never logged (they embed remote addresses and live in the
// discarded http.Server ErrorLog), and that the cert PATHS the boot
// summary logs by design carry no identifier-shaped bytes (generated
// under boring temp names).
package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nimna.app/relay/internal/wire"
)

// writeScrubCertPair generates a self-signed ECDSA P-256 certificate for
// 127.0.0.1 at TEST RUNTIME under boring names (cert.pem/key.pem in a
// plain temp dir) — the paths ARE logged by the boot summary, by design,
// so they must not be identifier-shaped; no key file is ever committed.
func writeScrubCertPair(t *testing.T) (certPath, keyPath string) {
	t.Helper()
	dir, err := os.MkdirTemp("", "nimna-logscrub-tls-*")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(dir) })
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "nimna-relay-logscrub"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(24 * time.Hour),
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		IPAddresses:           []net.IP{net.ParseIP("127.0.0.1")},
		IsCA:                  true,
		BasicConstraintsValid: true,
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	keyDER, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	certPath = filepath.Join(dir, "cert.pem")
	keyPath = filepath.Join(dir, "key.pem")
	if err := os.WriteFile(certPath,
		pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(keyPath,
		pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: keyDER}), 0o600); err != nil {
		t.Fatal(err)
	}
	return certPath, keyPath
}

// dialWSS dials the relay over wss:// with the test CA pool, recording
// the local address for the leak scan.
func (p *relayProc) dialWSS(rec *addrRecorder, pool *x509.CertPool) *scrubClient {
	p.t.Helper()
	hc := &http.Client{Transport: &http.Transport{
		TLSClientConfig: &tls.Config{RootCAs: pool},
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			c, err := net.Dial(network, addr)
			if err == nil {
				rec.record(c)
			}
			return c, err
		},
	}}
	ctx, cancel := context.WithTimeout(context.Background(), scrubTimeout)
	defer cancel()
	ws, _, err := websocket.Dial(ctx, "wss://"+p.addr, &websocket.DialOptions{HTTPClient: hc})
	if err != nil {
		p.t.Fatalf("wss dial: %v", err)
	}
	ws.SetReadLimit(-1)
	c := &scrubClient{t: p.t, ws: ws}
	p.t.Cleanup(func() { _ = ws.CloseNow() })
	return c
}

// TestLogScrubTLS drives the TLS surface of the real binary: boot with
// -tls-cert/-tls-key, full flows on both planes over wss://, and three
// deliberately failed handshakes (plain HTTP bytes at the TLS port, a
// 1.2-only ClientHello, an untrusting client that rejects the cert), then
// SIGTERM — and scrubs the entire output.
func TestLogScrubTLS(t *testing.T) {
	certPath, keyPath := writeScrubCertPair(t)
	pool := x509.NewCertPool()
	pemBytes, err := os.ReadFile(certPath)
	if err != nil {
		t.Fatal(err)
	}
	if !pool.AppendCertsFromPEM(pemBytes) {
		t.Fatal("no certs in pool PEM")
	}

	p := startRelay(t, "-tls-cert", certPath, "-tls-key", keyPath)
	rec := &addrRecorder{}

	// Known identifier bytes for the leak scan.
	topic := patterned(0x99)
	crid := patterned(0xAA)
	ids := map[string][]byte{
		"tls topic": topic[:],
		"tls crid":  crid[:],
	}

	// Real flows over wss://: rendezvous bridge + PAIR_DATA, then the
	// channel plane knock → accept → SESSION_DATA → TEARDOWN.
	a := p.dialWSS(rec, pool)
	b := p.dialWSS(rec, pool)
	a.send(wire.Encode(wire.RegisterTopic, topic, nil))
	b.send(wire.Encode(wire.RegisterTopic, topic, nil))
	bridged := wire.Encode(wire.TopicBridged, topic, nil)
	a.expect(bridged)
	b.expect(bridged)
	pd := wire.Encode(wire.PairData, topic, []byte("pairing bytes over tls"))
	a.send(pd)
	b.expect(pd)
	a.send(wire.Encode(wire.RegisterCRID, crid, nil))
	b.send(wire.Encode(wire.RegisterCRID, crid, nil))
	a.send(wire.Encode(wire.Knock, crid, nil))
	b.expect(wire.Encode(wire.KnockFwd, crid, nil))
	b.send(wire.Encode(wire.Accept, crid, nil))
	sb := wire.Encode(wire.SessionBridged, crid, nil)
	a.expect(sb)
	b.expect(sb)
	sd := wire.Encode(wire.SessionData, crid, []byte("ciphertext over tls"))
	a.send(sd)
	b.expect(sd)
	a.send(wire.Encode(wire.Teardown, crid, nil))
	b.expect(wire.Encode(wire.Teardown, crid, nil))
	_ = a.ws.CloseNow()
	_ = b.ws.CloseNow()

	// Handshake failures on purpose. Their errors embed our address —
	// they must go to the discarded ErrorLog, never the output.
	failedHandshake := func(name string, dial func(c net.Conn) error) {
		t.Helper()
		raw, err := net.Dial("tcp", p.addr)
		if err != nil {
			t.Fatalf("%s: dial: %v", name, err)
		}
		rec.record(raw)
		_ = raw.SetDeadline(time.Now().Add(scrubTimeout))
		if err := dial(raw); err == nil {
			t.Fatalf("%s: handshake unexpectedly succeeded", name)
		}
		_ = raw.Close()
	}
	// Plain HTTP bytes at the TLS port: stdlib answers with its fixed
	// plaintext 400 ("Client sent an HTTP request to an HTTPS server") —
	// state-independent stdlib behavior below the Nimna layer; what
	// matters here is that the failure produces NO log line.
	{
		raw, err := net.Dial("tcp", p.addr)
		if err != nil {
			t.Fatalf("plain HTTP probe: dial: %v", err)
		}
		rec.record(raw)
		_ = raw.SetDeadline(time.Now().Add(scrubTimeout))
		if _, err := raw.Write([]byte("GET / HTTP/1.1\r\nHost: relay\r\n\r\n")); err != nil {
			t.Fatalf("plain HTTP probe: write: %v", err)
		}
		drain := make([]byte, 4096)
		for {
			if _, err := raw.Read(drain); err != nil {
				break
			}
		}
		_ = raw.Close()
	}
	failedHandshake("1.2-only ClientHello", func(c net.Conn) error {
		return tls.Client(c, &tls.Config{
			RootCAs: pool, MaxVersion: tls.VersionTLS12, ServerName: "127.0.0.1",
		}).Handshake()
	})
	failedHandshake("untrusting client", func(c net.Conn) error {
		// System roots: the client aborts on the unknown CA, the server
		// sees a failed handshake (bad_certificate alert).
		return tls.Client(c, &tls.Config{ServerName: "127.0.0.1"}).Handshake()
	})

	p.terminate()
	out := p.out.String()

	// Positive controls: the TLS boot surface fired, with the paths (by
	// design — config values) and tls=on.
	for _, want := range []string{"relay listening", "config", "tls=on", certPath, keyPath, "relay stopped"} {
		if !strings.Contains(out, want) {
			t.Errorf("TLS output missing %q — the surface under scrub never fired", want)
		}
	}
	// Per-handshake errors are NEVER logged (§25): nothing
	// handshake-shaped may reach the output.
	for _, forbidden := range []string{"handshake", "http: TLS", "tls: "} {
		if strings.Contains(out, forbidden) {
			t.Errorf("output contains handshake-error text %q", forbidden)
		}
	}
	// No certificate material: paths yes, contents never.
	if strings.Contains(out, "BEGIN") {
		t.Error("output contains PEM material")
	}

	assertScrubbed(t, "TLS output", out, ids, rec.snapshot())
}
