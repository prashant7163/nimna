package push

import (
	"context"
	"errors"

	"nimna.app/relay/internal/ident"
	"nimna.app/relay/internal/wire"
)

// ErrNoTransport signals an intentional silent drop: a dispatch routed to
// a platform with no configured transport. The Dispatcher counts it as
// outcome="dropped" — the same best-effort class as queue overflow (§27:
// the label enumeration does not grow) — and logs nothing: a one-platform
// deployment is legal and spec-sanctioned (§3.2.1: self-hosters "run
// push-less" — or half-push-less).
var ErrNoTransport = errors.New("push: no transport configured for platform")

// Router implements Sender over the two optional real transports,
// routing on the platform byte from the KNOCK payload (0x01 APNs, 0x02
// FCM). Either sender may be nil; a dispatch for a missing platform is
// the ErrNoTransport silent drop. cmd/relay wires a Router whenever any
// real credential is configured; -push-sink and the Router are mutually
// exclusive (boot-fatal together, §24).
type Router struct {
	apns Sender
	fcm  Sender
}

// NewRouter builds a Router over the optional platform senders.
func NewRouter(apns, fcm Sender) *Router {
	return &Router{apns: apns, fcm: fcm}
}

// Send routes to the platform's transport, or reports the silent drop.
func (r *Router) Send(ctx context.Context, platform wire.Platform, token ident.DeviceToken) error {
	var s Sender
	switch platform {
	case wire.PlatformAPNs:
		s = r.apns
	case wire.PlatformFCM:
		s = r.fcm
	}
	if s == nil {
		return ErrNoTransport
	}
	return s.Send(ctx, platform, token)
}
