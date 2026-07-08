// APNs transport (architecture note §27; spec §3.2.1): HTTP/2 POST of the
// constant content-free body, authenticated by an ES256 provider JWT.
//
// Stdlib only, per the §11 pin executed in §27: no golang-jwt, no apns2 —
// JWT assembly here is fixed base64url/JSON encoding over a stdlib
// crypto/ecdsa signature (composition, not hand-rolled crypto), verified
// in tests against the public key. cmd/relay's import graph stays
// x/crypto-free (CI-asserted, anchored).
package push

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"nimna.app/relay/internal/ident"
	"nimna.app/relay/internal/wire"
)

const (
	// apnsDefaultBaseURL is the production endpoint (§27: the :2197
	// alternative is not used).
	apnsDefaultBaseURL = "https://api.push.apple.com"
	// APNsSandboxBaseURL is the development/sandbox host. Dev-build tokens
	// (an app signed with `aps-environment=development`) are only routable
	// here — the production host 400s them. Selected via -apns-sandbox
	// (S15), used for the deferred live-push device rung (PUBLISH_READY);
	// never in production.
	APNsSandboxBaseURL = "https://api.sandbox.push.apple.com"
	// apnsJWTMaxAge: the cached provider JWT is re-signed lazily once
	// this old — inside Apple's window (≥ 20 min between refreshes,
	// ≤ 60 min validity) with margin on both sides for clock skew.
	apnsJWTMaxAge = 40 * time.Minute
	// apnsExpiry is the apns-expiration horizon: now + the 60 s knock
	// window (§11 pin — a push landing after the pending knock expired
	// would wake the app onto nothing).
	apnsExpiry = 60 * time.Second
)

// APNsConfig configures the APNs Sender. The four credential slots are
// the §11-pinned quad (all-or-nothing, validated boot-fatally by
// cmd/relay before construction).
type APNsConfig struct {
	// KeyFile is the .p8 path: a PEM-encoded PKCS#8 ECDSA P-256 signing
	// key. It must parse at boot — a relay that discovers its key is
	// garbage at first dispatch has been silently push-less all along.
	KeyFile string
	// KeyID / TeamID fill the JWT (header kid, claim iss); Topic is the
	// apns-topic header (app bundle id).
	KeyID  string
	TeamID string
	Topic  string
	// BaseURL overrides the production endpoint — a constructor
	// parameter for tests ONLY (§27: no test knobs on the flag surface);
	// empty means production.
	BaseURL string
	// Now is the injectable clock (nil = time.Now).
	Now func() time.Time
}

// APNs is the production APNs Sender. One default-Transport http.Client,
// keep-alives on (APNs favors long-lived connections); HTTP/2 is
// negotiated transparently by net/http over TLS (asserted against the
// mock in tests). The cached JWT is an in-memory derivative of the
// credential config — recomputable, user-free, dies with the process
// (§27: spec §4's push-credential inventory item in working form).
type APNs struct {
	key    *ecdsa.PrivateKey
	keyID  string
	teamID string
	topic  string
	base   string
	now    func() time.Time
	client *http.Client

	// mu guards the JWT cache. The single dispatcher worker is the only
	// production caller (refresh is lazy and inline — zero new
	// goroutines); the mutex keeps the type safe regardless.
	mu       sync.Mutex
	jwt      string
	jwtBirth time.Time
}

// NewAPNs parses the .p8 and builds the Sender. Any error is boot-fatal
// at the caller: error text may name the configured path (operator
// config), never key material.
func NewAPNs(cfg APNsConfig) (*APNs, error) {
	key, err := loadAPNsKey(cfg.KeyFile)
	if err != nil {
		return nil, err
	}
	base := cfg.BaseURL
	if base == "" {
		base = apnsDefaultBaseURL
	}
	now := cfg.Now
	if now == nil {
		now = time.Now
	}
	return &APNs{
		key:    key,
		keyID:  cfg.KeyID,
		teamID: cfg.TeamID,
		topic:  cfg.Topic,
		base:   strings.TrimSuffix(base, "/"),
		now:    now,
		client: &http.Client{},
	}, nil
}

// loadAPNsKey reads and validates the .p8: PEM, PKCS#8, ECDSA P-256.
func loadAPNsKey(path string) (*ecdsa.PrivateKey, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("apns key: %w", err)
	}
	block, _ := pem.Decode(raw)
	if block == nil {
		return nil, fmt.Errorf("apns key %s: not PEM", path)
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("apns key %s: %w", path, err)
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("apns key %s: not an ECDSA key", path)
	}
	if key.Curve != elliptic.P256() {
		return nil, fmt.Errorf("apns key %s: not P-256", path)
	}
	return key, nil
}

// Send delivers one content-free wake: POST {base}/3/device/<hex(token)>
// with the §11-pinned constant headers and body. The KNOCK token field
// carries the platform-native token verbatim — for APNs the raw 32-byte
// binary device token, hex-encoded here into the URL path (the token
// bytes contract, §27). The response is drained and discarded, never
// parsed or logged; non-2xx surfaces as StatusError (status code only —
// a 410 on a stale token IS spec §3.2.1's "a push silently fails", and
// no token registry exists to act on it, by design).
func (a *APNs) Send(ctx context.Context, platform wire.Platform, token ident.DeviceToken) error {
	if platform != wire.PlatformAPNs {
		// Misrouted platform = the unconfigured-transport drop class;
		// the Router owns routing and never does this.
		return ErrNoTransport
	}
	bearer, err := a.bearer()
	if err != nil {
		return err
	}
	// WireBytes: sanctioned raw-token consumer — the platform call
	// itself (review-audited call site). Addressing lives in the URL
	// path; the body stays the byte-identical constant.
	url := a.base + "/3/device/" + hex.EncodeToString(token.WireBytes())
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, strings.NewReader(apnsBody))
	if err != nil {
		return err
	}
	req.Header.Set("authorization", "bearer "+bearer)
	req.Header.Set("apns-topic", a.topic)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "10")
	req.Header.Set("apns-expiration", strconv.FormatInt(a.now().Add(apnsExpiry).Unix(), 10))
	resp, err := a.client.Do(req)
	if err != nil {
		return err
	}
	return drainDiscard(resp)
}

// bearer returns the cached provider JWT, re-signing lazily at
// apnsJWTMaxAge — single-flight within the one dispatcher worker.
func (a *APNs) bearer() (string, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	now := a.now()
	if a.jwt != "" && now.Sub(a.jwtBirth) < apnsJWTMaxAge {
		return a.jwt, nil
	}
	jwt, err := a.signJWT(now)
	if err != nil {
		return "", err
	}
	a.jwt, a.jwtBirth = jwt, now
	return jwt, nil
}

// signJWT assembles the ES256 provider token: header {alg, kid}, claims
// {iss, iat}, JWS compact serialization (base64url raw), signature =
// ECDSA P-256 over SHA-256 of the signing input, encoded as the JWS
// fixed-width r‖s (32+32 bytes) — fixed encoding over a stdlib
// signature, nothing more.
func (a *APNs) signJWT(now time.Time) (string, error) {
	header, err := json.Marshal(struct {
		Alg string `json:"alg"`
		Kid string `json:"kid"`
	}{"ES256", a.keyID})
	if err != nil {
		return "", err
	}
	claims, err := json.Marshal(struct {
		Iss string `json:"iss"`
		Iat int64  `json:"iat"`
	}{a.teamID, now.Unix()})
	if err != nil {
		return "", err
	}
	b64 := base64.RawURLEncoding
	input := b64.EncodeToString(header) + "." + b64.EncodeToString(claims)
	digest := sha256.Sum256([]byte(input))
	r, s, err := ecdsa.Sign(rand.Reader, a.key, digest[:])
	if err != nil {
		return "", err
	}
	return input + "." + b64.EncodeToString(jwsSignatureES256(r, s)), nil
}

// jwsSignatureES256 encodes an ECDSA P-256 signature in the JWS ES256
// form: fixed-width r‖s, each value left-padded with zeros to exactly 32
// bytes (RFC 7518 §3.4 — NOT ASN.1). The padding matters: roughly 1 in
// 128 signatures has a short r or s, and an unpadded encoding would
// produce a JWT the platform rejects intermittently. Deterministically
// unit-tested with short values (the probabilistic path alone would let
// a padding bug survive most runs).
func jwsSignatureES256(r, s *big.Int) []byte {
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	return sig
}

// drainDiscard applies the §27 response posture shared by both real
// transports: drain a bounded amount (connection reuse), discard, never
// parse, never log; non-2xx becomes StatusError — the status code is the
// only detail that may reach the operational log.
func drainDiscard(resp *http.Response) error {
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
	if cerr := resp.Body.Close(); cerr != nil {
		return cerr
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return &StatusError{Code: resp.StatusCode}
	}
	return nil
}

var _ Sender = (*APNs)(nil)
