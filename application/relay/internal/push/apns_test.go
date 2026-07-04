package push

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"nimna.app/relay/internal/wire"
)

// writeTestP8 generates a fresh ECDSA P-256 key at TEST RUNTIME and
// serializes it as a .p8 (PEM PKCS#8) under dir. No key-shaped file is
// ever committed (§27 — the history secret scan stays unambiguous).
func writeTestP8(t *testing.T, dir string) (path string, pub *ecdsa.PublicKey) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatalf("marshal PKCS#8: %v", err)
	}
	path = filepath.Join(dir, "test-signing-key.p8")
	buf := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})
	if err := os.WriteFile(path, buf, 0o600); err != nil {
		t.Fatalf("write .p8: %v", err)
	}
	return path, &key.PublicKey
}

// jwtParts splits a compact JWS and decodes its three segments.
func jwtParts(t *testing.T, token string) (header, claims map[string]any, input string, sig []byte) {
	t.Helper()
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		t.Fatalf("jwt: %d segments, want 3", len(parts))
	}
	dec := func(s string) []byte {
		b, err := base64.RawURLEncoding.DecodeString(s)
		if err != nil {
			t.Fatalf("jwt segment not raw base64url: %v", err)
		}
		return b
	}
	if err := json.Unmarshal(dec(parts[0]), &header); err != nil {
		t.Fatalf("jwt header: %v", err)
	}
	if err := json.Unmarshal(dec(parts[1]), &claims); err != nil {
		t.Fatalf("jwt claims: %v", err)
	}
	return header, claims, parts[0] + "." + parts[1], dec(parts[2])
}

// verifyES256 checks a JWS ES256 signature (fixed-width r‖s) against pub.
func verifyES256(t *testing.T, pub *ecdsa.PublicKey, input string, sig []byte) {
	t.Helper()
	if len(sig) != 64 {
		t.Fatalf("ES256 signature: %d bytes, want 64 (r‖s)", len(sig))
	}
	digest := sha256.Sum256([]byte(input))
	r := new(big.Int).SetBytes(sig[:32])
	s := new(big.Int).SetBytes(sig[32:])
	if !ecdsa.Verify(pub, digest[:], r, s) {
		t.Fatal("ES256 signature does not verify against the public key")
	}
}

// apnsRecord captures one request the mock platform saw.
type apnsRecord struct {
	protoMajor int
	path       string
	headers    http.Header
	body       []byte
}

type apnsMock struct {
	mu   sync.Mutex
	reqs []apnsRecord
}

func (m *apnsMock) handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := readAll(r)
		m.mu.Lock()
		m.reqs = append(m.reqs, apnsRecord{
			protoMajor: r.ProtoMajor,
			path:       r.URL.Path,
			headers:    r.Header.Clone(),
			body:       body,
		})
		m.mu.Unlock()
	})
}

func readAll(r *http.Request) ([]byte, error) {
	var buf bytes.Buffer
	_, err := buf.ReadFrom(r.Body)
	return buf.Bytes(), err
}

func (m *apnsMock) snapshot() []apnsRecord {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]apnsRecord(nil), m.reqs...)
}

// startAPNsMock runs an h2-enabled TLS server (APNs requires HTTP/2; the
// test asserts requests actually arrive over it).
func startAPNsMock(t *testing.T, h http.Handler) *httptest.Server {
	t.Helper()
	srv := httptest.NewUnstartedServer(h)
	srv.EnableHTTP2 = true
	srv.StartTLS()
	t.Cleanup(srv.Close)
	return srv
}

// newTestAPNs builds a sender against the mock, pointing its client at
// the mock's root CA / h2 transport (in-package reach into the unexported
// field — the public constructor surface stays base-URL-only, §27).
func newTestAPNs(t *testing.T, srv *httptest.Server, now func() time.Time) (*APNs, *ecdsa.PublicKey) {
	t.Helper()
	p8, pub := writeTestP8(t, t.TempDir())
	a, err := NewAPNs(APNsConfig{
		KeyFile: p8,
		KeyID:   "TESTKEYID1",
		TeamID:  "TESTTEAM01",
		Topic:   "app.nimna",
		BaseURL: srv.URL,
		Now:     now,
	})
	if err != nil {
		t.Fatalf("NewAPNs: %v", err)
	}
	a.client = srv.Client()
	return a, pub
}

// TestAPNsExactRequestShape: HTTP/2, hex-token path addressing, the
// §11-pinned constant headers and body, byte-identical bodies across
// sends, and a verifiable ES256 JWT.
func TestAPNsExactRequestShape(t *testing.T) {
	mock := &apnsMock{}
	srv := startAPNsMock(t, mock.handler())
	clock := time.Date(2026, 7, 4, 12, 0, 0, 0, time.UTC)
	a, pub := newTestAPNs(t, srv, func() time.Time { return clock })

	tok1 := token(0x5A, 32) // APNs form: raw 32-byte binary device token
	tok2 := token(0xC4, 32)
	if err := a.Send(context.Background(), wire.PlatformAPNs, tok1); err != nil {
		t.Fatalf("Send 1: %v", err)
	}
	if err := a.Send(context.Background(), wire.PlatformAPNs, tok2); err != nil {
		t.Fatalf("Send 2: %v", err)
	}

	reqs := mock.snapshot()
	if len(reqs) != 2 {
		t.Fatalf("requests: got %d, want 2", len(reqs))
	}

	// h2 negotiated by stdlib over TLS (§27 assertion).
	for i, r := range reqs {
		if r.protoMajor != 2 {
			t.Errorf("request %d arrived over HTTP/%d, want HTTP/2", i, r.protoMajor)
		}
	}

	// Addressing = the URL path, token hex-encoded (token bytes
	// contract: KNOCK carries the raw 32 bytes; the relay hex-encodes).
	if want := "/3/device/" + strings.Repeat("5a", 32); reqs[0].path != want {
		t.Errorf("path: got %q, want %q", reqs[0].path, want)
	}
	if want := "/3/device/" + strings.Repeat("c4", 32); reqs[1].path != want {
		t.Errorf("path: got %q, want %q", reqs[1].path, want)
	}

	// The §11 constant headers, exactly.
	h := reqs[0].headers
	if got := h.Get("apns-topic"); got != "app.nimna" {
		t.Errorf("apns-topic: %q", got)
	}
	if got := h.Get("apns-push-type"); got != "alert" {
		t.Errorf("apns-push-type: %q", got)
	}
	if got := h.Get("apns-priority"); got != "10" {
		t.Errorf("apns-priority: %q", got)
	}
	wantExp := strconv.FormatInt(clock.Add(60*time.Second).Unix(), 10)
	if got := h.Get("apns-expiration"); got != wantExp {
		t.Errorf("apns-expiration: got %q, want now+60s = %q", got, wantExp)
	}

	// The header SET is closed: nothing beyond the five pinned headers
	// plus Go's implicit transport headers may appear — a sixth
	// per-dispatch header would be an unaudited variation channel. And
	// across sends the relay-authored headers are identical (addressing
	// is the URL path alone; the clock is fixed here).
	allowed := map[string]bool{}
	for _, k := range []string{
		// The §11 pinned set.
		"authorization", "apns-topic", "apns-push-type", "apns-priority",
		"apns-expiration",
		// Go transport implicits (client/h2 layer, not relay-authored).
		"user-agent", "accept-encoding", "content-length", "content-type",
	} {
		allowed[http.CanonicalHeaderKey(k)] = true
	}
	for i, r := range reqs {
		for k := range r.headers {
			if !allowed[http.CanonicalHeaderKey(k)] {
				t.Errorf("request %d: unexpected header %q — the APNs header set is pinned", i, k)
			}
		}
		for _, k := range []string{"authorization", "apns-topic", "apns-push-type", "apns-priority", "apns-expiration"} {
			if got, want := r.headers.Get(k), reqs[0].headers.Get(k); got != want {
				t.Errorf("request %d: header %s varies across sends: %q vs %q", i, k, got, want)
			}
		}
	}

	// Body: the pinned constant, byte-identical across sends — the
	// auditable content-freeness claim (addressing never enters it).
	if string(reqs[0].body) != apnsBody {
		t.Errorf("body: got %q, want the pinned constant", reqs[0].body)
	}
	if !bytes.Equal(reqs[0].body, reqs[1].body) {
		t.Error("bodies must be byte-identical across sends")
	}
	for i, r := range reqs {
		if bytes.Contains(bytes.ToLower(r.body), []byte(strings.Repeat("5a", 32))) ||
			bytes.Contains(bytes.ToLower(r.body), []byte(strings.Repeat("c4", 32))) {
			t.Errorf("request %d: token bytes leaked into the body", i)
		}
	}

	// The bearer JWT: shape and a real signature against the public key.
	auth := h.Get("authorization")
	if !strings.HasPrefix(auth, "bearer ") {
		t.Fatalf("authorization: %q, want a bearer token", auth)
	}
	header, claims, input, sig := jwtParts(t, strings.TrimPrefix(auth, "bearer "))
	if header["alg"] != "ES256" || header["kid"] != "TESTKEYID1" || len(header) != 2 {
		t.Errorf("jwt header: %v, want exactly {alg: ES256, kid: TESTKEYID1}", header)
	}
	if claims["iss"] != "TESTTEAM01" || int64(claims["iat"].(float64)) != clock.Unix() || len(claims) != 2 {
		t.Errorf("jwt claims: %v, want exactly {iss: TESTTEAM01, iat: %d}", claims, clock.Unix())
	}
	verifyES256(t, pub, input, sig)
}

// TestAPNsJWTCacheAndResign: the JWT is reused below 40 min of age and
// lazily re-signed past it (injectable clock; both tokens verify).
func TestAPNsJWTCacheAndResign(t *testing.T) {
	mock := &apnsMock{}
	srv := startAPNsMock(t, mock.handler())
	clock := time.Date(2026, 7, 4, 12, 0, 0, 0, time.UTC)
	var mu sync.Mutex
	now := func() time.Time { mu.Lock(); defer mu.Unlock(); return clock }
	advance := func(d time.Duration) { mu.Lock(); clock = clock.Add(d); mu.Unlock() }
	a, pub := newTestAPNs(t, srv, now)

	tok := token(0x01, 32)
	ctx := context.Background()
	mustSend := func() {
		t.Helper()
		if err := a.Send(ctx, wire.PlatformAPNs, tok); err != nil {
			t.Fatalf("Send: %v", err)
		}
	}
	mustSend()
	advance(39 * time.Minute) // still inside the 40 min window
	mustSend()
	advance(2 * time.Minute) // 41 min old: must re-sign
	mustSend()

	reqs := mock.snapshot()
	if len(reqs) != 3 {
		t.Fatalf("requests: got %d, want 3", len(reqs))
	}
	jwt0 := reqs[0].headers.Get("authorization")
	jwt1 := reqs[1].headers.Get("authorization")
	jwt2 := reqs[2].headers.Get("authorization")
	if jwt0 != jwt1 {
		t.Error("JWT must be cached and reused inside the 40 min window")
	}
	if jwt2 == jwt1 {
		t.Error("JWT must be re-signed once 40 min old")
	}
	_, claims, input, sig := jwtParts(t, strings.TrimPrefix(jwt2, "bearer "))
	verifyES256(t, pub, input, sig)
	if got := int64(claims["iat"].(float64)); got != now().Unix() {
		t.Errorf("re-signed iat: got %d, want %d", got, now().Unix())
	}
}

// TestAPNsStatusError: a non-2xx platform response surfaces as
// StatusError carrying the code and nothing else — APNs 410 on a stale
// token IS spec §3.2.1's "a push silently fails".
func TestAPNsStatusError(t *testing.T) {
	srv := startAPNsMock(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusGone)
	}))
	a, _ := newTestAPNs(t, srv, nil)
	err := a.Send(context.Background(), wire.PlatformAPNs, token(0x02, 32))
	var se *StatusError
	if !errors.As(err, &se) || se.Code != http.StatusGone {
		t.Fatalf("Send: got %v, want *StatusError{410}", err)
	}
}

// TestAPNsMisroutedPlatformDrops: a non-APNs platform byte is the
// silent-drop class, never a network call.
func TestAPNsMisroutedPlatformDrops(t *testing.T) {
	mock := &apnsMock{}
	srv := startAPNsMock(t, mock.handler())
	a, _ := newTestAPNs(t, srv, nil)
	if err := a.Send(context.Background(), wire.PlatformFCM, token(0x03, 4)); !errors.Is(err, ErrNoTransport) {
		t.Fatalf("Send: got %v, want ErrNoTransport", err)
	}
	if len(mock.snapshot()) != 0 {
		t.Fatal("a misrouted dispatch must not reach the platform")
	}
}

// TestNewAPNsBootFatalOnBadKey: the .p8 must parse at boot (§27) — a
// missing file, non-PEM bytes, and a non-P-256 key are all constructor
// errors, and none embeds key material.
func TestNewAPNsBootFatalOnBadKey(t *testing.T) {
	dir := t.TempDir()
	garbage := filepath.Join(dir, "garbage.p8")
	if err := os.WriteFile(garbage, []byte("not a key at all"), 0o600); err != nil {
		t.Fatal(err)
	}
	for name, path := range map[string]string{
		"missing file": filepath.Join(dir, "nope.p8"),
		"not PEM":      garbage,
	} {
		if _, err := NewAPNs(APNsConfig{KeyFile: path, KeyID: "K", TeamID: "T", Topic: "app.nimna"}); err == nil {
			t.Errorf("%s: NewAPNs accepted an unusable key", name)
		}
	}
}

// TestJWSSignatureES256FixedWidth pins the RFC 7518 §3.4 encoding
// DETERMINISTICALLY: short r/s values (≈1-in-128 per real signature, so
// the probabilistic JWT tests alone would let a padding bug survive most
// runs) must be left-padded with zeros to exactly 32 bytes each.
func TestJWSSignatureES256FixedWidth(t *testing.T) {
	full := new(big.Int).Lsh(big.NewInt(1), 255) // exactly 32 bytes, high bit set
	fullBytes := full.Bytes()
	if len(fullBytes) != 32 {
		t.Fatalf("test setup: full-width value is %d bytes", len(fullBytes))
	}
	short := big.NewInt(0x0102) // 2 bytes: needs 30 bytes of left padding

	cases := map[string]struct {
		r, s             *big.Int
		wantR31, wantS31 byte // last byte of each half
	}{
		"short r, full s": {short, full, 0x02, fullBytes[31]},
		"full r, short s": {full, short, fullBytes[31], 0x02},
		"both short":      {short, short, 0x02, 0x02},
		"both full":       {full, full, fullBytes[31], fullBytes[31]},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			sig := jwsSignatureES256(c.r, c.s)
			if len(sig) != 64 {
				t.Fatalf("signature length: got %d, want 64", len(sig))
			}
			// Each half must decode back to the exact input value —
			// i.e., the value sits right-aligned with zero left-padding.
			if got := new(big.Int).SetBytes(sig[:32]); got.Cmp(c.r) != 0 {
				t.Errorf("r half round-trip: got %v, want %v", got, c.r)
			}
			if got := new(big.Int).SetBytes(sig[32:]); got.Cmp(c.s) != 0 {
				t.Errorf("s half round-trip: got %v, want %v", got, c.s)
			}
			if sig[31] != c.wantR31 || sig[63] != c.wantS31 {
				t.Errorf("half boundaries: got r[31]=%#x s[31]=%#x, want %#x/%#x",
					sig[31], sig[63], c.wantR31, c.wantS31)
			}
			// The padding itself: everything left of the value bytes is zero.
			for i := 0; i < 32-len(c.r.Bytes()); i++ {
				if sig[i] != 0 {
					t.Fatalf("r half byte %d not zero-padded: %#x", i, sig[i])
				}
			}
			for i := 0; i < 32-len(c.s.Bytes()); i++ {
				if sig[32+i] != 0 {
					t.Fatalf("s half byte %d not zero-padded: %#x", i, sig[32+i])
				}
			}
		})
	}
}
