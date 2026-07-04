// Package push implements stateless push forwarding (spec §3.2.1;
// architecture note §11): when a valid knock finds no other live
// connection registered on the CRID and carries a device-token, the relay
// makes exactly ONE content-free outbound call, then discards the token.
//
// Content-freeness is structural: Sender's call surface has no content
// parameter — it physically cannot carry channel, sender, or message data.
// The platform request bodies are compile-time constants, byte-identical
// across all pushes except addressing; that constancy IS the auditable
// claim (spec §4: "auditors verify push behavior in the open code").
//
// Token lifecycle — discarded, not zeroed: a token's entire life is KNOCK
// payload → ident.DeviceToken at the parse boundary → one queue entry →
// one Send → garbage. It never enters internal/channel and never lands in
// state that outlives its dispatch; it is unloggable by type. Explicit
// zeroing is deliberately not done — the bytes are already in transport
// buffers beyond our reach, so it would be unverifiable theater; the
// guarantee that matters, NEVER STORED, is structural.
//
// Push is best-effort by spec (§3.2.1: a stale token "silently fails"; the
// fallback is out-of-band coordination): a full queue and a failed send
// are both silent drops. S5's metrics count aggregate failures.
//
// Real APNs/FCM transports are Session 6 (deploy) work behind this same
// Sender interface — stdlib-only, per the architecture note §11 pin. Until
// then the config-gated HTTPSink stands in for the platform during
// done-checks; with nothing configured the relay runs push-less.
package push

import (
	"context"
	"encoding/hex"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"nimna.app/relay/internal/ident"
	"nimna.app/relay/internal/wire"
)

// queueCap bounds the dispatch queue: the relay never queues beyond a
// fixed cap (spec §4 statelessness class); overflow drops silently.
const queueCap = 32

// sendTimeout bounds one delivery attempt.
const sendTimeout = 10 * time.Second

// Sender delivers one content-free wake to a device. There is NO content
// parameter — the notification body is a constant inside each Sender. The
// platform byte comes straight from the KNOCK payload; the token is used
// for this one call and then discarded by the caller.
type Sender interface {
	Send(ctx context.Context, platform wire.Platform, token ident.DeviceToken) error
}

// job is one queued dispatch: addressing only, no content by construction.
type job struct {
	platform wire.Platform
	token    ident.DeviceToken
}

// Dispatcher bounds the router against a slow push transport: a bounded
// queue drained by ONE worker goroutine with a per-attempt timeout.
// Enqueue never blocks the read goroutine that calls it.
type Dispatcher struct {
	sender Sender
	queue  chan job
}

// NewDispatcher wraps sender. Call Run to start the worker.
func NewDispatcher(sender Sender) *Dispatcher {
	return &Dispatcher{sender: sender, queue: make(chan job, queueCap)}
}

// Enqueue queues one dispatch without ever blocking. A full queue drops
// the push silently — push is best-effort by spec, and the relay never
// queues unboundedly.
func (d *Dispatcher) Enqueue(platform wire.Platform, token ident.DeviceToken) {
	select {
	case d.queue <- job{platform: platform, token: token}:
	default:
	}
}

// Run drains the queue with one worker until ctx is done. Send errors are
// discarded at S4 (best-effort; S5's metrics count aggregate failures).
// Jobs still queued at shutdown die with the process, like every other
// in-memory table.
func (d *Dispatcher) Run(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case j := <-d.queue:
			sctx, cancel := context.WithTimeout(ctx, sendTimeout)
			_ = d.sender.Send(sctx, j.platform, j.token)
			cancel()
		}
	}
}

// Content-free platform bodies, pinned in architecture note §11: a single
// constant localization key and nothing else — no channel, sender, count,
// or timestamp. The app bundle localizes NEW_ACTIVITY client-side; the
// relay never carries localized text. Byte-identical across all pushes of
// a platform.
const (
	apnsBody = `{"aps":{"alert":{"loc-key":"NEW_ACTIVITY"}}}`
	fcmBody  = `{"message":{"android":{"priority":"high","ttl":"60s","notification":{"title_loc_key":"NEW_ACTIVITY"}}}}`
)

// HTTPSink is the config-gated mock sink (-push-sink /
// NIMNA_RELAY_PUSH_SINK): it POSTs each dispatch to a local URL, standing
// in for the push platform — which legitimately receives the token, so the
// token travels as a header. Done-checks and, at S6, ops smoke tests
// assert on what it receives; it is never a production transport.
type HTTPSink struct {
	url    string
	client *http.Client
}

// NewHTTPSink returns a sink POSTing to url. The per-attempt timeout comes
// from the Dispatcher's Send context.
func NewHTTPSink(url string) *HTTPSink {
	return &HTTPSink{url: url, client: &http.Client{}}
}

// Send POSTs the constant platform body with the addressing headers
// Nimna-Push-Platform and Nimna-Push-Token. The body carries no token and
// no per-knock data of any kind.
func (s *HTTPSink) Send(ctx context.Context, platform wire.Platform, token ident.DeviceToken) error {
	var body, name string
	switch platform {
	case wire.PlatformAPNs:
		body, name = apnsBody, "apns"
	case wire.PlatformFCM:
		body, name = fcmBody, "fcm"
	default:
		// Unreachable from the wire: the KNOCK parser admits only the
		// two platform bytes. Dropped silently by the dispatcher.
		return errors.New("push: unknown platform")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.url, strings.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Nimna-Push-Platform", name)
	// WireBytes: the one sanctioned raw-token consumer — the platform
	// call itself (review-audited call site).
	req.Header.Set("Nimna-Push-Token", hex.EncodeToString(token.WireBytes()))
	resp, err := s.client.Do(req)
	if err != nil {
		return err
	}
	// Drain a bounded amount so the connection can be reused.
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
	return resp.Body.Close()
}
