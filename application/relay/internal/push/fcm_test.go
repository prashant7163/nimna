package push

import (
	"bytes"
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"nimna.app/relay/internal/ident"
	"nimna.app/relay/internal/wire"
)

// writeTestSA generates a fresh RSA key at TEST RUNTIME and serializes it
// into a service-account JSON shape under dir, pointing token_uri at the
// mock (§27: the SA file itself carries the injection point). No
// key-shaped file is ever committed.
func writeTestSA(t *testing.T, dir, tokenURI string) (path string, pub *rsa.PublicKey) {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatalf("marshal PKCS#8: %v", err)
	}
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})
	sa, err := json.Marshal(map[string]string{
		"type":         "service_account",
		"client_email": "test-sender@test-project.iam.gserviceaccount.com",
		"private_key":  string(keyPEM),
		"token_uri":    tokenURI,
		"project_id":   "test-project",
	})
	if err != nil {
		t.Fatal(err)
	}
	path = filepath.Join(dir, "test-service-account.json")
	if err := os.WriteFile(path, sa, 0o600); err != nil {
		t.Fatalf("write SA json: %v", err)
	}
	return path, &key.PublicKey
}

// fcmRecord captures one request the mock platform saw.
type fcmRecord struct {
	path    string
	headers http.Header
	form    map[string]string // token grants only
	body    []byte            // messages:send only
}

// fcmMock serves both the OAuth token endpoint (/token) and the v1
// messages:send endpoint from one TLS server.
type fcmMock struct {
	mu       sync.Mutex
	grants   []fcmRecord
	sends    []fcmRecord
	grantsIn int // access tokens minted so far (distinct values)
}

func (m *fcmMock) handler(t *testing.T) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/token":
			if err := r.ParseForm(); err != nil {
				t.Errorf("token grant: bad form: %v", err)
			}
			m.mu.Lock()
			m.grantsIn++
			n := m.grantsIn
			m.grants = append(m.grants, fcmRecord{
				path:    r.URL.Path,
				headers: r.Header.Clone(),
				form: map[string]string{
					"grant_type": r.PostFormValue("grant_type"),
					"assertion":  r.PostFormValue("assertion"),
				},
			})
			m.mu.Unlock()
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"access_token":"test-access-token-%d","expires_in":3600}`, n)
		default:
			body, _ := readAll(r)
			m.mu.Lock()
			m.sends = append(m.sends, fcmRecord{
				path:    r.URL.Path,
				headers: r.Header.Clone(),
				body:    body,
			})
			m.mu.Unlock()
		}
	})
}

func (m *fcmMock) snapshot() (grants, sends []fcmRecord) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]fcmRecord(nil), m.grants...), append([]fcmRecord(nil), m.sends...)
}

// verifyRS256 checks a JWS RS256 signature against pub.
func verifyRS256(t *testing.T, pub *rsa.PublicKey, input string, sig []byte) {
	t.Helper()
	digest := sha256.Sum256([]byte(input))
	if err := rsa.VerifyPKCS1v15(pub, crypto.SHA256, digest[:], sig); err != nil {
		t.Fatalf("RS256 signature does not verify against the public key: %v", err)
	}
}

// newTestFCM builds a sender against one mock server carrying both
// endpoints (in-package client override; the public constructor surface
// stays base-URL-only, §27).
func newTestFCM(t *testing.T, srv *httptest.Server, now func() time.Time) (*FCM, *rsa.PublicKey) {
	t.Helper()
	saPath, pub := writeTestSA(t, t.TempDir(), srv.URL+"/token")
	f, err := NewFCM(FCMConfig{SAFile: saPath, BaseURL: srv.URL, Now: now})
	if err != nil {
		t.Fatalf("NewFCM: %v", err)
	}
	f.client = srv.Client()
	return f, pub
}

// TestFCMExactRequestShape: the JWT-bearer grant (verifiable RS256
// assertion, exact claims), then messages:send with the constant
// template plus exactly one addressing field — message.token — and
// byte-identical bodies across sends modulo that field.
func TestFCMExactRequestShape(t *testing.T) {
	mock := &fcmMock{}
	srv := httptest.NewTLSServer(mock.handler(t))
	t.Cleanup(srv.Close)
	clock := time.Date(2026, 7, 4, 12, 0, 0, 0, time.UTC)
	f, pub := newTestFCM(t, srv, func() time.Time { return clock })

	// FCM form: the registration token's ASCII bytes, verbatim.
	tokA := ident.DeviceTokenFrom([]byte("registration-token-A"))
	tokB := ident.DeviceTokenFrom([]byte("registration-token-B"))
	if err := f.Send(context.Background(), wire.PlatformFCM, tokA); err != nil {
		t.Fatalf("Send A: %v", err)
	}
	if err := f.Send(context.Background(), wire.PlatformFCM, tokB); err != nil {
		t.Fatalf("Send B: %v", err)
	}

	grants, sends := mock.snapshot()
	if len(grants) != 1 {
		t.Fatalf("token grants: got %d, want 1 (the token is cached)", len(grants))
	}
	if len(sends) != 2 {
		t.Fatalf("sends: got %d, want 2", len(sends))
	}

	// The grant: form fields and a verifiable RS256 assertion.
	g := grants[0]
	if g.form["grant_type"] != fcmGrantType {
		t.Errorf("grant_type: %q", g.form["grant_type"])
	}
	header, claims, input, sig := jwtParts(t, g.form["assertion"])
	if header["alg"] != "RS256" || header["typ"] != "JWT" || len(header) != 2 {
		t.Errorf("jwt header: %v, want exactly {alg: RS256, typ: JWT}", header)
	}
	wantClaims := map[string]any{
		"iss":   "test-sender@test-project.iam.gserviceaccount.com",
		"scope": fcmScope,
		"aud":   srv.URL + "/token",
	}
	for k, want := range wantClaims {
		if claims[k] != want {
			t.Errorf("jwt claim %s: got %v, want %v", k, claims[k], want)
		}
	}
	iat := int64(claims["iat"].(float64))
	exp := int64(claims["exp"].(float64))
	if iat != clock.Unix() || exp != iat+3600 {
		t.Errorf("jwt iat/exp: got %d/%d, want %d/%d", iat, exp, clock.Unix(), clock.Unix()+3600)
	}
	if len(claims) != 5 {
		t.Errorf("jwt claims: %v, want exactly {iss, scope, aud, iat, exp}", claims)
	}
	verifyRS256(t, pub, input, sig)

	// messages:send: path, bearer, content type, exact body.
	s0, s1 := sends[0], sends[1]
	if want := "/v1/projects/test-project/messages:send"; s0.path != want {
		t.Errorf("send path: got %q, want %q", s0.path, want)
	}
	if got := s0.headers.Get("Authorization"); got != "Bearer test-access-token-1" {
		t.Errorf("Authorization: %q", got)
	}
	if got := s0.headers.Get("Content-Type"); got != "application/json" {
		t.Errorf("Content-Type: %q", got)
	}

	// The exact §11 body: constant template + exactly one per-dispatch
	// field, message.token, built by json.Marshal of the fixed struct.
	wantBody := func(tok string) string {
		return `{"message":{"android":{"priority":"high","ttl":"60s","notification":{"title_loc_key":"NEW_ACTIVITY"}},"token":"` + tok + `"}}`
	}
	if string(s0.body) != wantBody("registration-token-A") {
		t.Errorf("body A: got %q", s0.body)
	}
	if string(s1.body) != wantBody("registration-token-B") {
		t.Errorf("body B: got %q", s1.body)
	}
	// Byte-identical modulo the one addressing field.
	if !bytes.Equal(
		bytes.ReplaceAll(s0.body, []byte("registration-token-A"), nil),
		bytes.ReplaceAll(s1.body, []byte("registration-token-B"), nil),
	) {
		t.Error("bodies must be byte-identical except message.token")
	}
}

// TestFCMTokenCacheAndRefresh: the access token is cached until
// expiry − 5 min and refreshed lazily inline past it (injectable clock).
func TestFCMTokenCacheAndRefresh(t *testing.T) {
	mock := &fcmMock{}
	srv := httptest.NewTLSServer(mock.handler(t))
	t.Cleanup(srv.Close)
	clock := time.Date(2026, 7, 4, 12, 0, 0, 0, time.UTC)
	var mu sync.Mutex
	now := func() time.Time { mu.Lock(); defer mu.Unlock(); return clock }
	advance := func(d time.Duration) { mu.Lock(); clock = clock.Add(d); mu.Unlock() }
	f, _ := newTestFCM(t, srv, now)

	tok := ident.DeviceTokenFrom([]byte("reg-token"))
	ctx := context.Background()
	mustSend := func() {
		t.Helper()
		if err := f.Send(ctx, wire.PlatformFCM, tok); err != nil {
			t.Fatalf("Send: %v", err)
		}
	}
	mustSend()                // grant #1 (expires_in 3600)
	advance(54 * time.Minute) // still before expiry − 5 min
	mustSend()                // cached
	advance(2 * time.Minute)  // 56 min: inside the 5 min slack window
	mustSend()                // grant #2

	grants, sends := mock.snapshot()
	if len(grants) != 2 {
		t.Fatalf("token grants: got %d, want 2 (cache until expiry − 5 min)", len(grants))
	}
	if len(sends) != 3 {
		t.Fatalf("sends: got %d, want 3", len(sends))
	}
	if got := sends[1].headers.Get("Authorization"); got != "Bearer test-access-token-1" {
		t.Errorf("cached send Authorization: %q", got)
	}
	if got := sends[2].headers.Get("Authorization"); got != "Bearer test-access-token-2" {
		t.Errorf("refreshed send Authorization: %q", got)
	}
}

// TestFCMStatusErrors: non-2xx from messages:send AND from the grant
// endpoint both surface as StatusError — the status code is the only
// detail the operational log may carry (FCM 404 on a stale token IS spec
// §3.2.1's "a push silently fails").
func TestFCMStatusErrors(t *testing.T) {
	t.Run("send 404", func(t *testing.T) {
		srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path == "/token" {
				w.Header().Set("Content-Type", "application/json")
				fmt.Fprint(w, `{"access_token":"tok","expires_in":3600}`)
				return
			}
			w.WriteHeader(http.StatusNotFound)
		}))
		t.Cleanup(srv.Close)
		f, _ := newTestFCM(t, srv, nil)
		err := f.Send(context.Background(), wire.PlatformFCM, ident.DeviceTokenFrom([]byte("stale")))
		var se *StatusError
		if !errors.As(err, &se) || se.Code != http.StatusNotFound {
			t.Fatalf("Send: got %v, want *StatusError{404}", err)
		}
	})
	t.Run("grant 500", func(t *testing.T) {
		srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusInternalServerError)
		}))
		t.Cleanup(srv.Close)
		f, _ := newTestFCM(t, srv, nil)
		err := f.Send(context.Background(), wire.PlatformFCM, ident.DeviceTokenFrom([]byte("x")))
		var se *StatusError
		if !errors.As(err, &se) || se.Code != http.StatusInternalServerError {
			t.Fatalf("Send: got %v, want *StatusError{500}", err)
		}
	})
}

// TestFCMMisroutedPlatformDrops: a non-FCM platform byte is the
// silent-drop class, never a network call.
func TestFCMMisroutedPlatformDrops(t *testing.T) {
	mock := &fcmMock{}
	srv := httptest.NewTLSServer(mock.handler(t))
	t.Cleanup(srv.Close)
	f, _ := newTestFCM(t, srv, nil)
	if err := f.Send(context.Background(), wire.PlatformAPNs, token(0x03, 4)); !errors.Is(err, ErrNoTransport) {
		t.Fatalf("Send: got %v, want ErrNoTransport", err)
	}
	if g, s := mock.snapshot(); len(g) != 0 || len(s) != 0 {
		t.Fatal("a misrouted dispatch must not reach the platform")
	}
}

// TestNewFCMBootFatal: the SA file must parse at boot (§27) — missing
// file, invalid JSON, missing fields, and a garbage key are all
// constructor errors.
func TestNewFCMBootFatal(t *testing.T) {
	dir := t.TempDir()
	write := func(name, content string) string {
		t.Helper()
		p := filepath.Join(dir, name)
		if err := os.WriteFile(p, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
		return p
	}
	cases := map[string]string{
		"missing file": filepath.Join(dir, "nope.json"),
		"not JSON":     write("garbage.json", "not json"),
		"missing fields": write("partial.json",
			`{"client_email":"a@b","token_uri":"https://x/token"}`),
		"garbage key": write("badkey.json",
			`{"client_email":"a@b","private_key":"not a pem","token_uri":"https://x/token","project_id":"p"}`),
	}
	for name, path := range cases {
		if _, err := NewFCM(FCMConfig{SAFile: path}); err == nil {
			t.Errorf("%s: NewFCM accepted an unusable service account", name)
		} else if strings.Contains(err.Error(), "PRIVATE KEY") {
			t.Errorf("%s: constructor error must not embed key material: %v", name, err)
		}
	}

	// The missing-fields error is deterministic: EVERY missing field,
	// sorted, names only (the APNs-quad error style) — never one
	// arbitrary field per run.
	_, err := NewFCM(FCMConfig{SAFile: cases["missing fields"]})
	if err == nil {
		t.Fatal("missing fields: NewFCM accepted the file")
	}
	if !strings.Contains(err.Error(), "missing private_key,project_id") {
		t.Errorf("missing-fields error must list all missing fields sorted: %v", err)
	}
}
