# assets/

Bundled static assets. Index for the leaf folders below (per the repo
README discipline).

## fonts/

Vendored typefaces — committed, never fetched at build or runtime
(`google_fonts` is permanently rejected: runtime fetch = phone-home;
app-architecture.md §8.5). Downloaded from github.com/google/fonts (OFL
directories); each folder carries the upstream `OFL.txt` license text.

- `fonts/schibsted_grotesk/SchibstedGrotesk-wght.ttf` — variable-weight
  TTF (upstream file `SchibstedGrotesk[wght].ttf`, renamed only to avoid
  brackets in asset paths). Weights 400/500/600 are selected via
  `FontVariation('wght', …)` in `lib/src/ui/theme/nimna_tokens.dart`.
- `fonts/spline_sans_mono/SplineSansMono-wght.ttf` — variable-weight TTF
  (upstream `SplineSansMono[wght].ttf`); weight 500 only, used solely for
  machine-shaped strings (Nimna code, safety phrase).

## wordlist/ (S9)

- `wordlist/wordlist-en-v1.txt` — the pinned safety-phrase wordlist (EFF
  short wordlist 2.0, 1296 words), a verbatim copy of the normative
  `docs/test-vectors/wordlist-en-v1.txt`. **Protocol output, not UI copy:**
  one global list, rendered identically in every locale (spec §3.1.4). Its
  SHA-256 is normative and is verified at load time by
  `lib/src/pairing/joiner/safety_phrase_wordlist.dart` (fail-closed on
  drift). Never localized, never edited outside a spec change.
