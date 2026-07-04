package limits

import (
	"context"
	"net"
	"sync"
	"sync/atomic"
	"time"

	"nimna.app/relay/internal/ident"
	"nimna.app/relay/internal/metrics"
)

// Listener defaults (architecture note §§14, 16–17).
const (
	// DefaultMaxConnsPerIP is generous for CGNAT households sharing one
	// v4 address, tiny against single-VPS capacity.
	DefaultMaxConnsPerIP = 64
	// DefaultIdleTimeout is three missed 30 s client ping intervals —
	// §3.3's own missed-ping heuristic, relay-side.
	DefaultIdleTimeout = 90 * time.Second
)

// ListenerConfig configures a Listener. Zero values mean the defaults.
type ListenerConfig struct {
	MaxConnsPerIP int
	IdleTimeout   time.Duration
	// Metrics receives conn_ip and idle limit trips; nil is a no-op
	// instrument.
	Metrics *metrics.Metrics
	// Now is the injectable clock (nil = time.Now).
	Now func() time.Time
}

// Listener is the limit listener (§17): a net.Listener wrapper around the
// raw TCP listener and the single home for all transport-boundary
// enforcement — per-IP connection accounting and the liveness deadline.
// S6 ordering, pinned: raw TCP → Listener → tls.NewListener → HTTP, so
// over-cap abusers cost zero TLS handshakes and the liveness clock counts
// ciphertext bytes (liveness is a transport-level property).
//
// An over-cap connect is closed at the TCP accept boundary with zero
// bytes written; the refusal is a pure function of the connecting IP
// key's own live-connection count and of no Nimna registry state — an
// over-cap client experiences only connection loss, byte-identical
// against an empty relay and a loaded one (§16).
type Listener struct {
	net.Listener
	maxPerIP int
	idle     time.Duration
	m        *metrics.Metrics
	now      func() time.Time

	mu    sync.Mutex
	perIP map[ident.RemoteAddr]int
	conns map[*Conn]struct{}
}

// NewListener wraps ln.
func NewListener(ln net.Listener, cfg ListenerConfig) *Listener {
	if cfg.MaxConnsPerIP <= 0 {
		cfg.MaxConnsPerIP = DefaultMaxConnsPerIP
	}
	if cfg.IdleTimeout <= 0 {
		cfg.IdleTimeout = DefaultIdleTimeout
	}
	if cfg.Now == nil {
		cfg.Now = time.Now
	}
	return &Listener{
		Listener: ln,
		maxPerIP: cfg.MaxConnsPerIP,
		idle:     cfg.IdleTimeout,
		m:        cfg.Metrics,
		now:      cfg.Now,
		perIP:    make(map[ident.RemoteAddr]int),
		conns:    make(map[*Conn]struct{}),
	}
}

// Accept accepts the next connection, enforcing the per-IP cap: an
// at-cap connection is closed immediately with zero bytes written —
// pre-Nimna, pre-HTTP (and at S6 pre-TLS) — and the accept loop
// continues. HTTP 429 was considered and rejected (§16): it spends HTTP
// parsing on exactly the traffic the cap exists to shed and adds a
// fingerprintable response surface where zero bytes is available.
func (l *Listener) Accept() (net.Conn, error) {
	for {
		raw, err := l.Listener.Accept()
		if err != nil {
			return nil, err
		}
		key := ident.RemoteAddrFrom(raw.RemoteAddr().String())

		l.mu.Lock()
		if l.perIP[key] >= l.maxPerIP {
			l.mu.Unlock()
			l.m.Trip(metrics.LimitConnIP)
			_ = raw.Close()
			continue
		}
		l.perIP[key]++
		c := &Conn{Conn: raw, l: l, key: key}
		c.touch()
		l.conns[c] = struct{}{}
		l.mu.Unlock()

		// OS-level TCP keepalive backstop for the write path, Go
		// defaults (§17): the wrapper deadline is the enforced bound;
		// keepalive only catches peers whose stack is dead.
		if tcp, ok := raw.(*net.TCPConn); ok {
			_ = tcp.SetKeepAlive(true)
		}
		return c, nil
	}
}

// drop unregisters c (once, from Conn.Close).
func (l *Listener) drop(c *Conn) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if _, ok := l.conns[c]; !ok {
		return
	}
	delete(l.conns, c)
	if l.perIP[c.key] <= 1 {
		delete(l.perIP, c.key)
	} else {
		l.perIP[c.key]--
	}
}

// sweep closes connections whose last inbound activity is older than the
// idle deadline. The close surfaces as a read error in the WebSocket
// loop, whose normal teardown unwinds both planes' registrations; the
// close itself is a bare transport close — no Nimna bytes (§16).
func (l *Listener) sweep() {
	deadline := l.now().Add(-l.idle).UnixNano()
	l.mu.Lock()
	var reap []*Conn
	for c := range l.conns {
		if c.last.Load() < deadline {
			reap = append(reap, c)
		}
	}
	l.mu.Unlock()
	for _, c := range reap {
		c.idleClosed.Store(true)
		l.m.Trip(metrics.LimitIdle)
		_ = c.Close()
	}
}

// janitorTick derives the liveness sweep interval: deadline/3 capped at
// 30 s — exactly the §17 30 s tick at the 90 s default, scaling down
// with config-accelerated deadlines so the reap bound stays deadline +
// tick ≤ 4/3 × deadline (90–120 s at defaults).
func (l *Listener) janitorTick() time.Duration {
	tick := l.idle / 3
	if tick > 30*time.Second {
		tick = 30 * time.Second
	}
	if tick < 10*time.Millisecond {
		tick = 10 * time.Millisecond
	}
	return tick
}

// RunJanitor sweeps until ctx is done (§22: joins the relay's context
// path; no drain).
func (l *Listener) RunJanitor(ctx context.Context) {
	tick := time.NewTicker(l.janitorTick())
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
			l.sweep()
		}
	}
}

// Len reports live tracked connections — an identifier-free count.
func (l *Listener) Len() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return len(l.conns)
}

// Conn is one tracked connection: it bumps the last-inbound-byte clock in
// Read — WebSocket pings are inbound bytes, so pings count as liveness
// structurally (§17; the §12 constraint, satisfied without a ping
// callback the library doesn't offer).
type Conn struct {
	net.Conn
	l          *Listener
	key        ident.RemoteAddr
	last       atomic.Int64 // UnixNano of the last inbound byte
	idleClosed atomic.Bool
	closeOnce  sync.Once
}

func (c *Conn) touch() { c.last.Store(c.l.now().UnixNano()) }

// Read updates the liveness clock on any inbound bytes.
func (c *Conn) Read(b []byte) (int, error) {
	n, err := c.Conn.Read(b)
	if n > 0 {
		c.touch()
	}
	return n, err
}

// Close unregisters the connection exactly once, then closes the
// transport.
func (c *Conn) Close() error {
	var err error
	c.closeOnce.Do(func() {
		c.l.drop(c)
		err = c.Conn.Close()
	})
	return err
}

// RemoteKey is the canonicalized per-IP key (ident.RemoteAddr — port
// stripped, IPv6 /64). The server reuses it so the accept boundary and
// the HTTP layer key identically.
func (c *Conn) RemoteKey() ident.RemoteAddr { return c.key }

// IdleClosed reports whether the liveness janitor closed this connection
// (the server attributes the close class from it).
func (c *Conn) IdleClosed() bool { return c.idleClosed.Load() }
