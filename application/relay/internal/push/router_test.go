package push

import (
	"context"
	"errors"
	"log/slog"
	"strings"
	"testing"

	"nimna.app/relay/internal/metrics"
	"nimna.app/relay/internal/wire"
)

// TestRouterRoutesOnPlatformByte: 0x01 → the APNs sender, 0x02 → the FCM
// sender, addressing preserved.
func TestRouterRoutesOnPlatformByte(t *testing.T) {
	apns := newMockSender(false)
	fcm := newMockSender(false)
	r := NewRouter(apns, fcm)

	if err := r.Send(context.Background(), wire.PlatformAPNs, token(0xA1, 32)); err != nil {
		t.Fatalf("APNs route: %v", err)
	}
	if err := r.Send(context.Background(), wire.PlatformFCM, token(0xB2, 8)); err != nil {
		t.Fatalf("FCM route: %v", err)
	}

	a, f := apns.snapshot(), fcm.snapshot()
	if len(a) != 1 || a[0].platform != wire.PlatformAPNs || a[0].tokenHex != strings.Repeat("a1", 32) {
		t.Fatalf("APNs sender saw %v", a)
	}
	if len(f) != 1 || f[0].platform != wire.PlatformFCM || f[0].tokenHex != strings.Repeat("b2", 8) {
		t.Fatalf("FCM sender saw %v", f)
	}
}

// TestRouterUnconfiguredPlatformIsSilentDrop: a dispatch for a platform
// with no sender returns ErrNoTransport, and through the Dispatcher it is
// counted outcome="dropped" — the enumeration does not grow — with NO log
// line (a one-platform deployment is legal, §3.2.1/§27).
func TestRouterUnconfiguredPlatformIsSilentDrop(t *testing.T) {
	apns := newMockSender(false)
	r := NewRouter(apns, nil) // APNs-only deployment

	if err := r.Send(context.Background(), wire.PlatformFCM, token(0x01, 4)); !errors.Is(err, ErrNoTransport) {
		t.Fatalf("Send: got %v, want ErrNoTransport", err)
	}

	mtr := metrics.New()
	logBuf := &syncBuf{}
	d := NewDispatcher(r, mtr, slog.New(slog.NewTextHandler(logBuf, nil)))
	runDispatcher(t, d)

	d.Enqueue(wire.PlatformFCM, token(0x02, 4))  // dropped (no FCM sender)
	d.Enqueue(wire.PlatformAPNs, token(0x03, 4)) // sent
	apns.waitSends(t, 1)
	waitFor(t, func() bool { return pushCount(mtr, "dropped") == "1" },
		"dropped counter never reached 1")
	waitFor(t, func() bool { return pushCount(mtr, "sent") == "1" },
		"sent counter never reached 1")
	if pushCount(mtr, "failed") != "0" {
		t.Error("an unconfigured platform must not count as failed")
	}
	if out := logBuf.String(); strings.Contains(out, "push transport failure") {
		t.Errorf("an unconfigured-platform drop must not log: %q", out)
	}
}
