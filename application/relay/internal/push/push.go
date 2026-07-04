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
// are both silent drops ON THE WIRE. Off the wire, metrics count every
// outcome (sent/failed/dropped — the caps' refusals are counted by the
// caller), and a failed send logs one fixed-field Warn line carrying
// platform and HTTP status code ONLY — no token, no CRID, no error text
// (note §19: error strings can embed URLs and response fragments; the
// fixed fields cannot).
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
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"nimna.app/relay/internal/ident"
	"nimna.app/relay/internal/metrics"
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

// StatusError reports a transport-level HTTP status from a Sender — the
// ONLY error detail the operational log ever carries for a push (note
// §19). It deliberately holds no URL, token, header, or body fragment.
type StatusError struct{ Code int }

func (e *StatusError) Error() string {
	return fmt.Sprintf("push: transport status %d", e.Code)
}

// platformLabel renders the platform byte for the fixed-field log line —
// a two-value compile-time enumeration, never wire bytes.
func platformLabel(p wire.Platform) string {
	switch p {
	case wire.PlatformAPNs:
		return "apns"
	case wire.PlatformFCM:
		return "fcm"
	}
	return "unknown"
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
	m      *metrics.Metrics
	log    *slog.Logger
}

// NewDispatcher wraps sender. Call Run to start the worker. m may be nil
// (a no-op instrument); logger may be nil for silent operation (tests).
func NewDispatcher(sender Sender, m *metrics.Metrics, logger *slog.Logger) *Dispatcher {
	if logger == nil {
		logger = slog.New(slog.DiscardHandler)
	}
	return &Dispatcher{
		sender: sender,
		queue:  make(chan job, queueCap),
		m:      m,
		log:    logger,
	}
}

// Enqueue queues one dispatch without ever blocking. A full queue drops
// the push silently on the wire — push is best-effort by spec, and the
// relay never queues unboundedly; the drop is counted.
func (d *Dispatcher) Enqueue(platform wire.Platform, token ident.DeviceToken) {
	select {
	case d.queue <- job{platform: platform, token: token}:
	default:
		d.m.Push(metrics.PushDropped)
	}
}

// Run drains the queue with one worker until ctx is done. Every attempt
// is counted: sent, failed (with the fixed-field Warn line — platform and
// HTTP status only, status 0 when the transport produced no HTTP
// response, never the error's own rendering; note §19), or dropped when
// the Sender reports ErrNoTransport (a dispatch for an unconfigured
// platform: silent, unlogged — the same best-effort class as queue
// overflow, §27). Jobs still queued at shutdown die with the process,
// like every other in-memory table.
func (d *Dispatcher) Run(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case j := <-d.queue:
			sctx, cancel := context.WithTimeout(ctx, sendTimeout)
			err := d.sender.Send(sctx, j.platform, j.token)
			cancel()
			if err == nil {
				d.m.Push(metrics.PushSent)
				continue
			}
			if errors.Is(err, ErrNoTransport) {
				d.m.Push(metrics.PushDropped)
				continue
			}
			d.m.Push(metrics.PushFailed)
			status := 0
			var se *StatusError
			if errors.As(err, &se) {
				status = se.Code
			}
			d.log.Warn("push transport failure",
				"platform", platformLabel(j.platform), "status", status)
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
	if cerr := resp.Body.Close(); cerr != nil {
		return cerr
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		// The status code is the ONLY detail surfaced: it feeds the
		// fixed-field transport-status log line (note §19).
		return &StatusError{Code: resp.StatusCode}
	}
	return nil
}
