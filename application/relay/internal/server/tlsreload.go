package server

import (
	"crypto/tls"
	"crypto/x509"
	"log/slog"
	"os"
	"sync/atomic"
	"time"
)

// certStatThrottle bounds certificate-file stats to at most one per 60 s
// (architecture note §25): the reload check is handshake-driven — no
// goroutine, no timer — so an idle relay pays nothing and a busy one pays
// one os.Stat a minute.
const certStatThrottle = 60 * time.Second

// certReloader is the §25 in-process certificate reloader behind
// tls.Config.GetCertificate: it holds the current certificate in an
// atomic.Pointer and, at most once per throttle window, stats the cert
// file and reloads the pair when its mtime moves — certbot renewal is a
// pure file copy (deploy/certbot-deploy-hook.sh) and live sessions
// survive it; no restart, no SIGHUP verb.
//
// Failure posture: the initial load is boot-fatal (a relay that cannot
// serve its configured certificate must not come up); a later reload
// failure KEEPS SERVING the old certificate and logs one fixed Warn line
// per attempt. TLS log events are exactly §25's exhaustive set — boot
// summary (cmd/relay), reload success (leaf notAfter only), reload
// failure (operator-owned file errors; paths are config, never user
// data). Per-handshake errors are never logged: they embed remote
// addresses and stay in the http.Server ErrorLog we discard.
type certReloader struct {
	certPath, keyPath string
	log               *slog.Logger
	now               func() time.Time
	throttle          time.Duration

	cert     atomic.Pointer[tls.Certificate]
	mtime    atomic.Int64 // UnixNano of the loaded cert file's mtime
	lastStat atomic.Int64 // UnixNano of the last stat attempt (throttle)
}

// newCertReloader loads the pair once (the caller treats an error as
// boot-fatal). now nil means time.Now; throttle 0 means the pinned 60 s
// (tests inject both).
func newCertReloader(certPath, keyPath string, logger *slog.Logger, now func() time.Time, throttle time.Duration) (*certReloader, error) {
	if logger == nil {
		logger = slog.New(slog.DiscardHandler)
	}
	if now == nil {
		now = time.Now
	}
	if throttle <= 0 {
		throttle = certStatThrottle
	}
	r := &certReloader{
		certPath: certPath,
		keyPath:  keyPath,
		log:      logger,
		now:      now,
		throttle: throttle,
	}
	cert, err := tls.LoadX509KeyPair(certPath, keyPath)
	if err != nil {
		return nil, err
	}
	r.cert.Store(&cert)
	if fi, err := os.Stat(certPath); err == nil {
		r.mtime.Store(fi.ModTime().UnixNano())
	}
	r.lastStat.Store(now().UnixNano())
	return r, nil
}

// GetCertificate is the tls.Config hook: it opportunistically checks for
// a renewed certificate (throttled), then returns the current one. It
// never fails a handshake over a reload problem — the old certificate
// keeps serving.
func (r *certReloader) GetCertificate(*tls.ClientHelloInfo) (*tls.Certificate, error) {
	r.maybeReload()
	return r.cert.Load(), nil
}

// maybeReload stats the cert file at most once per throttle window
// (single-flight via CAS — concurrent handshakes cannot stampede the
// filesystem) and reloads the pair when the mtime moved.
func (r *certReloader) maybeReload() {
	now := r.now().UnixNano()
	last := r.lastStat.Load()
	if now-last < int64(r.throttle) || !r.lastStat.CompareAndSwap(last, now) {
		return
	}
	fi, err := os.Stat(r.certPath)
	if err != nil {
		// Operator-owned file, fixed line; the error rendering may carry
		// the configured path (config, never user data) — §25.
		r.log.Warn("tls certificate reload failed; keeping the previous certificate", "err", err.Error())
		return
	}
	m := fi.ModTime().UnixNano()
	if m == r.mtime.Load() {
		return
	}
	cert, err := tls.LoadX509KeyPair(r.certPath, r.keyPath)
	if err != nil {
		r.log.Warn("tls certificate reload failed; keeping the previous certificate", "err", err.Error())
		return
	}
	r.cert.Store(&cert)
	r.mtime.Store(m)
	// Reload success: one Info line whose only variable is the new
	// leaf's notAfter — cert metadata, operator-relevant,
	// identifier-free (§25).
	r.log.Info("tls certificate reloaded", "not_after", leafNotAfter(&cert).UTC().Format(time.RFC3339))
}

// leafNotAfter extracts the leaf's NotAfter; the zero time if the leaf is
// unparseable (LoadX509KeyPair already validated the pair, so this is
// belt-and-braces).
func leafNotAfter(cert *tls.Certificate) time.Time {
	if cert.Leaf != nil {
		return cert.Leaf.NotAfter
	}
	if len(cert.Certificate) == 0 {
		return time.Time{}
	}
	leaf, err := x509.ParseCertificate(cert.Certificate[0])
	if err != nil {
		return time.Time{}
	}
	return leaf.NotAfter
}
