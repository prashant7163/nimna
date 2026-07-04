# nimna.app — Launch Checklist

## Placeholders that MUST be wired before launch
- [ ] **Store buttons** (`index.html`, two `.storebtn` links): replace `href="#"` with real App Store / Play Store URLs once listings exist.
- [ ] **Repo link** (all pages): currently `https://github.com/prashant7163/nimna`. The repo must be PUBLIC before launch or the "verify it yourself" claim is hollow — the site's trust argument depends on it.
- [ ] **Contact mailbox**: `hello@nimna.app` referenced on privacy/security/press — create the mailbox (or alias) before launch.
- [x] ~~Paywall price~~ RETIRED by spec v0.1.1 §10: no price number is ever published outside the stores — the site describes the model only, and the pricing section's store badges are the path to the real number. (2026-07-04)
- [ ] **Pricing-section store badges** (`index.html`, `.price-stores`): same wiring as the hero buttons — real store URLs at launch.
- [ ] `/security` page: update the cryptography section when spec v0.2 locks primitives; remove the "unfinished by our own admission" caveat only then.

## Meta & assets
- [x] Title/description on all four pages
- [x] OG + Twitter card tags with 1200×630 `og.png` (absolute URLs)
- [x] Canonical URLs on all pages
- [x] Favicon: SVG + 192/512 PNG + apple-touch-icon 180 (from the app icon)
- [x] `theme-color` #0B0B0C
- [ ] Verify OG rendering with a card debugger after DNS is live

## Quality gates
- [x] No external requests anywhere (fonts self-hosted; grep for `https?://` in HTML/CSS confirms only outbound *links*, no loaded resources)
- [x] `prefers-color-scheme` dark default + full light theme
- [x] `prefers-reduced-motion`: hero line renders static; relay packet renders static mid-relay; smooth-scroll disabled
- [x] Semantic landmarks (header/nav/main/section/footer), FAQ as native `<details>`, focus-visible styles, aria labels on icon links
- [x] Contrast: token pairs are the WCAG-verified set from `designs/brand/color-system.md`
- [x] Critical path < 100 KB: HTML ~18 KB + CSS ~13 KB + JS ~1.3 KB (fonts load with `font-display: swap`, non-blocking)
- [x] Link check: `python3 temp/check_links.py` → all internal links + assets resolve
- [ ] **Lighthouse ≥ 95 all categories** — run on the deployed URL (headless local runs under-report fonts/caching):
      `npx lighthouse https://nimna.app --view`
- [ ] Test 360 px width, iOS Safari + Android Chrome, dark and light

## Copy honesty (self-checked against protocol spec v0.1.1 — updated 2026-07-04)
- [x] Every architecture claim traced to spec §1/§4/§6 (no storage, no accounts, hash-only rendezvous, in-memory routing)
- [x] Metadata visibility stated on BOTH marketing and technical pages (IPs, timing, sizes, CRID; transient wake-token at knock time — spec §4 "necessarily sees", §3.2.1 disclosure)
- [x] Disappearing messages described as honor-system in both app-facing copy and FAQ ("a screenshot is still a screenshot") — spec §5
- [x] No cipher-level claims: primitives are TBD, and /security says so explicitly — spec §7
- [x] "Account-less", never "anonymous"; traffic correlation named as a v1 limitation — spec §9
- [x] Compelled-request answer limited to "nothing stored to produce" + live-connection metadata — spec §9 row 1
- [x] No fear marketing, no spy language, no "military-grade"
- [x] Pricing: yearly subscription, NO number anywhere, permanence guarantee stated wherever pricing is explained; "one-time"/"unlock" language purged — spec §10
- [x] Screenshots: detect-and-notify only, never prevention; honest limits (in-app only, second camera) on index + /security; FLAG_SECURE non-use stated — spec §5.2
- [x] Sensitive content: on-device only, "can't phone home", never blocked/logged/reported; /security + privacy table row — spec §5.3
- [x] Push: token forwarder-never-registry design on /security + privacy; the transient-linkage price + Apple/Google visibility stated plainly (honesty card + FAQ) — spec §3.2.1
- [x] Device loss: channels die by design, only the subscription restores, re-pair out-of-band; answered with confidence in FAQ — spec §6.1
- [x] Abuse posture: no discovery / strictly 1:1 / paid initiator on /security; residual two-bad-actors case admitted — spec §9
- [x] AGPL-3.0 named; code-vs-deployment credentials honesty; app-is-closed stated, not hidden — spec §4
