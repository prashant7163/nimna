# SESSION-DS — design-sync: reply/reaction UI, self-join surface, canonical strings (spec v0.2.1)

Branch `design-sync-reply-reactions` (worktree, based on main @ 604f767). USER-mandated
G1 third lane (DECISIONS 2026-07-05 02:58). Ownership: `designs/` + ARB stub handoff
only. Binding inputs for S9 (self-join surface) and S10 (reply/reaction UI).

## TASKS.md candidate line (fold at merge)

- **DS — design-sync reply/reactions/self-join** · implemented, ready for
  code-review + senior-qa · 2026-07-05 03:25 +0200 · designs/ synced v0.1.1 → v0.2.1;
  ARB stubs in designs/handoff/; hard prereq for S9 + S10 intake.

## PROGRESS.md candidate entries (fold at merge)

- **2026-07-05 03:25 +0200 · DS design-sync — implementation complete, pending review/QA.**
  Closed the four zero-coverage drift items from the v0.2.1 reconciliation
  (PROGRESS "SPEC RECONCILIATION", DECISIONS 2026-07-05 02:20): reactions, replies/quoting,
  the two canonical strings, the self-join guard. All additions reuse locked tokens/
  components verbatim — no new colors, no new type styles, no new icons (plus/close reused);
  amber appears nowhere in the new surfaces (a reaction is not a session event).
  Artifacts (all paths relative to repo root):
  - `designs/brand/voice-and-microcopy.md` — strings **19** (self-join canonical, spec §3.1
    verbatim), **20** (reply: "Replying to" overline, "Cancel reply" a11y, tombstone
    "Message no longer available." canonical verbatim, "Photo"/"Document" quoted-media
    labels), **21** (reactions: "React", chip a11y pair with {emoji}, "Choose another
    emoji"); 3 register notes (reactions are adjuncts — no delivery chrome ever; the
    tombstone never explains; self-join is guidance, not failure); 2 honesty-checklist
    items (no reaction delivered/seen claims; no tombstone reasons).
  - `designs/system/components.md` — new: **reaction chip** (geometry off the bubble's
    center-facing corner, ownership = stroke weight never color, add-replaces/
    remove-clears-unconditionally, adjunct lifetime — dies with referent, one-line
    clamp + bounded width vs hostile UTF-8 per the DECISIONS render note, zero delivery
    chrome — never ACKed), **message-actions card** (single long-press entry for
    react/reply/local-delete; six-preset emoji quick row + system-keyboard "+";
    one-grapheme compose rule enforced at entry), **quoted-reply preview** (local-render
    doctrine, in-bubble quote block + compose strip, tombstone state identical for
    unknown/deleted/expired, live-swap to tombstone when a referent dies later — never
    a cached excerpt), **code-entry own-code state** (self-join guard: warning-toned,
    no shake, Join disabled, relay never contacted; explicitly argued non-violation of
    the silence doctrine; guard scope = own outstanding codes only, so duplicate
    channels stay undetectable).
  - `designs/wireframes/f5-chat-session.html` — frames **F5.16** (long-press card),
    **F5.17** (chips on text + media, clamp + no-delivery-chrome annotations),
    **F5.18** (reply compose strip + quoted bubble), **F5.19 EDGE** (tombstone).
    `designs/wireframes/f3-join-channel.html` — **F3.8 EDGE** (self-join guard).
    All frames appended — existing numbering untouched. `wf.css` v0.2.1 block;
    README index 57 → 62 frames + new decisions/honesty notes. Chrome-render-verified.
  - `designs/screens/05-live-chat.html` + `.light.html` — reaction chip (theirs, ❤️ on
    the media bubble) + quoted reply composing with the disappearing timer (reply_to +
    expiry_s compose freely, spec §5.8); light sed-regenerated from dark per the
    established method. Net-new `designs/screens/16-message-actions.html` (long-press
    card state). `screens.css` v0.2.1 styles, token-exact. All three
    Chrome-render-verified at 438×900 (existing README method; script in worktree
    `temp/ds-render/`, git-ignored).
  - `designs/handoff/arb-stubs-reply-reactions.md` — 12 EN keys, namespaced `chat_…`/
    `pairing_…`, exact JSON incl. @-metadata + {emoji} placeholders; fold notes
    (no plurals needed; canonical values byte-locked; DE/FR/ES/IT ride S16 + the
    untranslated-key tracker). Live `lib/l10n` untouched (S7's, in flight).
  - READMEs updated: `designs/README.md`, `designs/brand/README.md`,
    `designs/system/README.md`, `designs/wireframes/README.md`,
    `designs/screens/README.md`, `designs/handoff/README.md`.
  Commits on this branch: fbb961a (voice guide) · 3494d66 (components) ·
  4a57399 (wireframes) · 0ce56e0 (hi-fi) · 9607b24 (ARB stubs + READMEs) ·
  + this progress file. Not claiming done — pending code-reviewer + senior-qa per
  the parallel-session pipeline.

## DECISIONS.md candidate entries (fold at merge; all CODE unless marked)

- **2026-07-05 03:25 +0200 · Reaction chips carry zero delivery chrome, including no
  waiting state · CODE** — a REACTION is never ACKed (spec §5.8), so ✓/pending would be
  unbackable claims; deliberately extended to the offline case: a reaction composed
  while the peer is offline rides the outbox silently with NO dashed-waiting variant —
  the chip is an adjunct on an existing bubble, not a message of its own, and "not yet
  sent" chrome on a chip would read as delivery state the instant it cleared ·
  alternatives: dashed chip while queued (honest about local state but manufactures a
  delivery-state vocabulary for a surface the protocol keeps stateless); suppress the
  chip until bridged (the sender's own act should render when made, like every compose).
- **2026-07-05 03:25 +0200 · Chip ownership = stroke weight, never color; chips never
  amber · CODE** — yours `textSecondary` stroke, theirs `hairline`; amber rationing
  says amber = session state/primary action only, and a reaction is neither ·
  alternative: amber-tint own chip (violates the rationing rule outright).
- **2026-07-05 03:25 +0200 · Hostile-UTF-8 clamp specced as a hard component rule ·
  CODE** — chip renders one line, bidi-isolated, content max-width 40 / chip max 60,
  clipped, never parsed (operationalizes the DECISIONS 2026-07-05 render-side note;
  the sender-side single-grapheme rule is never receiver-validated, spec §5.5/§5.8).
- **2026-07-05 03:25 +0200 · Quote block re-renders from live local state — swaps to
  the tombstone the moment its referent dies · CODE** — a cached excerpt would let
  quoted content outlive expiry/delete inside the quote, defeating §5.8's
  never-resurrect rule; the preview's only legitimate source is the local copy ·
  alternative: freeze the excerpt at receive time (violates inherit-expiry intent).
- **2026-07-05 03:25 +0200 · Self-join guard renders warning-toned, shake-free,
  distinct from wrong-code by design · CODE** — first product use of the `warning`
  token (color-system: "rare — code-TTL expiring notice" family; WCAG-verified both
  modes); danger styling would call the user's own code a failure, and the "one
  permitted shake" stays with wrong-code. Doctrine-safe distinctness: the silence
  doctrine's single generic response covers relay-facing foreign codes; self-join is
  local knowledge, nothing is sent · alternative: reuse the danger error state with
  different copy (misreads guidance as failure; also blurs the two states S9 must keep
  separate).
- **2026-07-05 03:25 +0200 · React/reply/delete share one long-press message-actions
  card · CODE** — single entry on the only legal referents (text + media manifest,
  spec §5.8); consolidates the previously documented long-press → Delete (F5.1) into
  the same card so long-press has one meaning product-wide · alternative: separate
  gestures per action (gesture inflation; double-tap-to-react conflicts with nothing
  today but spends a gesture budget v1 doesn't need).
- **2026-07-05 03:25 +0200 · v0.2.1 wireframe frames appended, never renumbered ·
  CODE** — F5.16–F5.19 + F3.8; existing frame IDs are referenced by annotations,
  READMEs, and prior PROGRESS entries — renumbering would corrupt the record.

## USER questions (consolidated — none blocking; proposed defaults shipped)

1. **Emoji quick-row preset set** (F5.16 / screen 16 / components message-actions):
   proposed default 👍 ❤️ 😂 😮 😢 🙏. Any single emoji remains reachable via the
   system keyboard "+", so the presets are pure convenience — taste, not doctrine.
   Confirm or replace before S10 freezes the composer surfaces.

## Spec/design conflicts found

- None. The v0.2.1 additions slotted into the existing system without contradicting
  any locked decision (silence doctrine, amber rationing, no-skip safety phrase,
  honor-system expiry language, numberless pricing all untouched). The one judgment
  call with doctrine texture — self-join rendering distinct from wrong-code — is
  argued above and in the F3.8 annotation; flagging for reviewer attention rather
  than as a conflict.

## Notes for the orchestrator

- ARB fold: `designs/handoff/arb-stubs-reply-reactions.md` → `lib/l10n` at merge
  (12 keys; two values byte-locked canonical). No pubspec additions, no routes —
  DS touches no code.
- Render-verification scripts live in worktree `temp/ds-render/` (git-ignored),
  per the scripts-in-temp rule.
