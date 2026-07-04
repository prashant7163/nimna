// FCM v1 transport (architecture note §27; spec §3.2.1): OAuth2
// JWT-bearer service-account grant, then POST of the constant
// content-free message with exactly one per-dispatch field —
// message.token.
//
// Stdlib only, per the §11 pin executed in §27: no x/oauth2, no Firebase
// SDK — the RS256 grant JWT is fixed base64url/JSON encoding over a
// stdlib crypto/rsa signature (composition, not hand-rolled crypto),
// verified in tests against the public key. cmd/relay's import graph
// stays x/crypto-free (CI-asserted, anchored).
package push

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	"nimna.app/relay/internal/ident"
	"nimna.app/relay/internal/wire"
)

const (
	// fcmDefaultBaseURL fronts the v1 messages:send endpoint; the OAuth
	// token endpoint comes from the service-account file's token_uri
	// (so a test SA file points the grant at the mock — §27).
	fcmDefaultBaseURL = "https://fcm.googleapis.com"
	// fcmScope is the JWT-bearer grant scope.
	fcmScope = "https://www.googleapis.com/auth/firebase.messaging"
	// fcmGrantType is the OAuth2 JWT-bearer grant type.
	fcmGrantType = "urn:ietf:params:oauth:grant-type:jwt-bearer"
	// fcmJWTValidity is the grant assertion's exp horizon (iat + 1 h).
	fcmJWTValidity = time.Hour
	// fcmTokenSlack: the cached access token is refreshed lazily once
	// within this margin of its expiry (cached until expiry − 5 min).
	fcmTokenSlack = 5 * time.Minute
)

// FCMConfig configures the FCM Sender.
type FCMConfig struct {
	// SAFile is the service-account JSON path (the §11 slot). It
	// supplies client_email, private_key, token_uri, and project_id —
	// no extra env slots — and must parse at boot (boot-fatal at the
	// caller otherwise).
	SAFile string
	// BaseURL overrides the production messages:send base — a
	// constructor parameter for tests ONLY (§27); empty = production.
	BaseURL string
	// Now is the injectable clock (nil = time.Now).
	Now func() time.Time
}

// serviceAccount is the minimal read of the SA JSON: exactly the four
// fields the transport needs, nothing else retained.
type serviceAccount struct {
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
	TokenURI    string `json:"token_uri"`
	ProjectID   string `json:"project_id"`
}

// FCM is the production FCM v1 Sender. One default-Transport
// http.Client, keep-alives on; the per-attempt bound is the dispatcher's
// send context — one timeout, not two. The cached access token is an
// in-memory derivative of the credential config — recomputable,
// user-free, dies with the process (§27).
type FCM struct {
	email    string
	tokenURI string
	project  string
	key      *rsa.PrivateKey
	base     string
	now      func() time.Time
	client   *http.Client

	// mu guards the access-token cache; refresh is lazy and inline on
	// the single dispatcher worker — zero new goroutines.
	mu          sync.Mutex
	accessToken string
	tokenExpiry time.Time
}

// NewFCM parses the service-account file and builds the Sender. Any
// error is boot-fatal at the caller: error text may name the configured
// path (operator config), never key material.
func NewFCM(cfg FCMConfig) (*FCM, error) {
	raw, err := os.ReadFile(cfg.SAFile)
	if err != nil {
		return nil, fmt.Errorf("fcm service account: %w", err)
	}
	var sa serviceAccount
	if err := json.Unmarshal(raw, &sa); err != nil {
		return nil, fmt.Errorf("fcm service account %s: %w", cfg.SAFile, err)
	}
	// One deterministic error naming EVERY missing field, sorted (field
	// names only, never values) — matching cmd/relay's APNs-quad style,
	// so the operator fixes the file in one pass.
	var missing []string
	for name, v := range map[string]string{
		"client_email": sa.ClientEmail,
		"private_key":  sa.PrivateKey,
		"token_uri":    sa.TokenURI,
		"project_id":   sa.ProjectID,
	} {
		if v == "" {
			missing = append(missing, name)
		}
	}
	if len(missing) > 0 {
		sort.Strings(missing)
		return nil, fmt.Errorf("fcm service account %s: missing %s",
			cfg.SAFile, strings.Join(missing, ","))
	}
	key, err := loadFCMKey(sa.PrivateKey, cfg.SAFile)
	if err != nil {
		return nil, err
	}
	base := cfg.BaseURL
	if base == "" {
		base = fcmDefaultBaseURL
	}
	now := cfg.Now
	if now == nil {
		now = time.Now
	}
	return &FCM{
		email:    sa.ClientEmail,
		tokenURI: sa.TokenURI,
		project:  sa.ProjectID,
		key:      key,
		base:     strings.TrimSuffix(base, "/"),
		now:      now,
		client:   &http.Client{},
	}, nil
}

// loadFCMKey parses the SA private_key PEM: PKCS#8 (Google's format),
// with a PKCS#1 fallback.
func loadFCMKey(pemStr, path string) (*rsa.PrivateKey, error) {
	block, _ := pem.Decode([]byte(pemStr))
	if block == nil {
		return nil, fmt.Errorf("fcm service account %s: private_key is not PEM", path)
	}
	if parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes); err == nil {
		key, ok := parsed.(*rsa.PrivateKey)
		if !ok {
			return nil, fmt.Errorf("fcm service account %s: private_key is not RSA", path)
		}
		return key, nil
	}
	key, err := x509.ParsePKCS1PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("fcm service account %s: private_key does not parse", path)
	}
	return key, nil
}

// fcmSendBody is the fixed message shape (§11 constants + the one
// addressing field), built by json.Marshal so escaping is correct and
// the shape is fixed: byte-identical across all pushes except the
// message.token value — §11's "byte-identical except addressing" made
// precise (for APNs the addressing is the URL path; for FCM it is this
// one field).
type fcmSendBody struct {
	Message struct {
		Android struct {
			Priority     string `json:"priority"`
			TTL          string `json:"ttl"`
			Notification struct {
				TitleLocKey string `json:"title_loc_key"`
			} `json:"notification"`
		} `json:"android"`
		Token string `json:"token"`
	} `json:"message"`
}

// Send delivers one content-free wake: POST
// {base}/v1/projects/<project>/messages:send under the cached OAuth2
// bearer. The KNOCK token field carries the platform-native token
// verbatim — for FCM the registration token's ASCII bytes, inserted as
// the JSON string value (the token bytes contract, §27). The response is
// drained and discarded, never parsed or logged; non-2xx surfaces as
// StatusError (a 404 on a stale token IS spec §3.2.1's "a push silently
// fails" — no feedback loop exists, by design).
func (f *FCM) Send(ctx context.Context, platform wire.Platform, token ident.DeviceToken) error {
	if platform != wire.PlatformFCM {
		// Misrouted platform = the unconfigured-transport drop class;
		// the Router owns routing and never does this.
		return ErrNoTransport
	}
	bearer, err := f.token(ctx)
	if err != nil {
		return err
	}
	var body fcmSendBody
	body.Message.Android.Priority = "high"
	body.Message.Android.TTL = "60s"
	body.Message.Android.Notification.TitleLocKey = "NEW_ACTIVITY"
	// WireBytes: sanctioned raw-token consumer — the platform call
	// itself (review-audited call site).
	body.Message.Token = string(token.WireBytes())
	payload, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		f.base+"/v1/projects/"+f.project+"/messages:send", strings.NewReader(string(payload)))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+bearer)
	req.Header.Set("Content-Type", "application/json")
	resp, err := f.client.Do(req)
	if err != nil {
		return err
	}
	return drainDiscard(resp)
}

// token returns the cached access token, refreshing lazily via the
// JWT-bearer grant once within fcmTokenSlack of expiry — single-flight
// within the one dispatcher worker.
func (f *FCM) token(ctx context.Context) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	now := f.now()
	if f.accessToken != "" && now.Before(f.tokenExpiry.Add(-fcmTokenSlack)) {
		return f.accessToken, nil
	}
	assertion, err := f.signJWT(now)
	if err != nil {
		return "", err
	}
	form := url.Values{
		"grant_type": {fcmGrantType},
		"assertion":  {assertion},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, f.tokenURI,
		strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := f.client.Do(req)
	if err != nil {
		return "", err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
		// The grant endpoint's status code is the only surfaced detail,
		// same posture as the platform call.
		return "", &StatusError{Code: resp.StatusCode}
	}
	// The grant response is the ONE response this package parses — the
	// access token cannot be extracted without reading it. Two fields,
	// bounded read, never logged.
	var grant struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int64  `json:"expires_in"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&grant); err != nil {
		return "", fmt.Errorf("fcm token grant: %w", err)
	}
	if grant.AccessToken == "" || grant.ExpiresIn <= 0 {
		return "", fmt.Errorf("fcm token grant: incomplete response")
	}
	f.accessToken = grant.AccessToken
	f.tokenExpiry = now.Add(time.Duration(grant.ExpiresIn) * time.Second)
	return f.accessToken, nil
}

// signJWT assembles the RS256 grant assertion: header {alg, typ}, claims
// {iss, scope, aud, iat, exp = iat + 1 h}, JWS compact serialization
// (base64url raw), signature = RSASSA-PKCS1-v1_5 over SHA-256 — fixed
// encoding over a stdlib signature, nothing more.
func (f *FCM) signJWT(now time.Time) (string, error) {
	header, err := json.Marshal(struct {
		Alg string `json:"alg"`
		Typ string `json:"typ"`
	}{"RS256", "JWT"})
	if err != nil {
		return "", err
	}
	iat := now.Unix()
	claims, err := json.Marshal(struct {
		Iss   string `json:"iss"`
		Scope string `json:"scope"`
		Aud   string `json:"aud"`
		Iat   int64  `json:"iat"`
		Exp   int64  `json:"exp"`
	}{f.email, fcmScope, f.tokenURI, iat, iat + int64(fcmJWTValidity/time.Second)})
	if err != nil {
		return "", err
	}
	b64 := base64.RawURLEncoding
	input := b64.EncodeToString(header) + "." + b64.EncodeToString(claims)
	digest := sha256.Sum256([]byte(input))
	sig, err := rsa.SignPKCS1v15(rand.Reader, f.key, crypto.SHA256, digest[:])
	if err != nil {
		return "", err
	}
	return input + "." + b64.EncodeToString(sig), nil
}

var _ Sender = (*FCM)(nil)
