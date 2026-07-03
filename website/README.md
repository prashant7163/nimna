# nimna.app — static site

The public website for Nimna. Pure static files: semantic HTML + one CSS file + one small JS file. **No frameworks, no build step, no external requests** — fonts are self-hosted, there are no analytics, no cookies, no third-party anything. The site practices what the product preaches.

## Structure

```
website/
├── index.html            # single scrolling page (hero → how → architecture → live-only
│                         #   → discretion → honesty → pricing → FAQ → footer)
├── privacy/index.html    # the near-empty privacy policy
├── security/index.html   # the protocol for technical readers
├── press/index.html      # boilerplate, logo + screenshot downloads, contact
├── assets/
│   ├── site.css          # all styles; tokens verbatim from designs/system/tokens.json
│   ├── site.js           # hero line draw + relay animation (~40 lines, no deps)
│   ├── fonts/            # Schibsted Grotesk 400/500/600 + Spline Sans Mono 500 (woff2, OFL)
│   ├── img/              # favicon.svg, icon-192/512, apple-touch-icon, og.png
│   └── press/            # downloadable logos + screenshots
└── launch-checklist.md
```

## Local preview

Any static server from this directory:

```sh
cd website
python3 -m http.server 8080
# → http://localhost:8080
```

(Opening `index.html` via `file://` also works; sub-page links use directory paths, so a server is truer to production.)

## Deploy

Any static host. Two known-good options:

**Cloudflare Pages** — create project → direct upload or connect the repo → set build output directory to `website`, no build command. Custom domain `nimna.app`; Cloudflare handles TLS.

**GitHub Pages** — serve the `website/` folder (e.g., a `gh-pages` branch containing its contents, or Actions upload-pages-artifact with `path: website`). Add a `CNAME` file containing `nimna.app` if using the custom domain.

Recommended headers if the host allows (Cloudflare `_headers` file):

```
/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer
  Permissions-Policy: camera=(), microphone=(), geolocation=()
  Content-Security-Policy: default-src 'self'; img-src 'self'; style-src 'self'; script-src 'self'; font-src 'self'
```

(The CSP is honest: the site genuinely needs nothing beyond `'self'`.)

## Before-launch placeholders

See `launch-checklist.md` — store-badge links, the GitHub repo going public, and the contact mailbox are wired as placeholders on purpose.
