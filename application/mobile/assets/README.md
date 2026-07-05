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
