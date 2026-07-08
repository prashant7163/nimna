# lib/src/session/chat/

The widget lane of the live session (S11 extends it). It wires a
`SessionController` to widgets and renders immutable `MessageView`s — it holds no
protocol state (no transport/key/counter/store; the import-direction fence). Every
user-facing string comes from l10n; left/right is never hardcoded. BINDING to
`designs/system/components.md`.

- `chat_screen.dart` — wires the controller to the composer, bubbles, and actions
  card, and renders the session-status line. No protocol logic; reads the
  controller's `messages`/`lineState`/`peerTyping` and forwards intent. [S14] owns
  the `ScreenshotDetector` lifecycle (start while mounted = content on screen, stop
  on dispose → `controller.noticeLocalScreenshot()`), interleaves the screenshot
  system lines into the thread by anchor (never re-sorting messages), and threads
  the `SensitiveContentAnalyzer` down to received-image bubbles + the attach whisper.
  [S16] gains OPTIONAL presence props (all defaulting off, so a bare ChatScreen is
  unchanged): `onKnock` renders the F5.1/F5.13 Knock / Knock again affordance + the
  compose-while-not-on-the-line surface (peer-offline empty state + "WAITING — ON
  YOUR PHONE ONLY" outbox header, spec §3.4); `knockDeadline` drives the screen-11
  waiting banner + countdown; `knockLapsed`/`knockStaleHint` the "No answer." + §6.1
  hint; `reconnectPhase` overrides the status line with the dropped/recovered/lost
  caption; `autoStart` (false under `LinePresence`) yields connection-lane ownership
  so the CRID is never double-registered.
- `line_presence.dart` — [S16] the FOREGROUND presence-mount coordinator for ONE
  open line (the F4-row-tap trigger). Owns exactly one controller at a time and maps
  the pure S8–S12 presence controllers (knock / incoming-knock / reconnect) → the
  postures: LISTENING (accepter, receivable) → Knock (disposes the listener FIRST,
  then a fresh knocker — the one-CRID invariant) → screen-11 waiting → lapse
  "No answer."/re-listen; or an inbound KNOCK_FWD → the F6 `IncomingKnockView` →
  explicit pick-up (NO auto-ACCEPT) → live; on live, adopts the controller into a
  `ReconnectCoordinator`. Presence scope is the single open line only — a knock to a
  line you don't have open (or a backgrounded app past the ~30 s grace) is the
  content-free push-wake path, device-deferred to S18. `IncomingKnockView` is the
  pure stateless F6 surface (label + "is knocking." + countdown + Pick up / Ignore).
- `message_bubble.dart` — text bubble + delivery ticks (dashed "WAITING — ON YOUR
  PHONE ONLY" / delivered check), the quoted-reply preview + neutral tombstone,
  reaction chips (ownership by STROKE weight, never color, never amber; one-line
  bidi-isolated clamp), and the silent peer-typing three-dot glyph. Also home of
  `sanitizeEmojiForA11y` — the REQUIRED sanitizer that bounds the wire's 64-byte
  emoji field and strips C0/C1 + bidi/format controls before it enters any a11y
  announcement (keeps ZWJ / variation selectors / skin-tone modifiers).
- `message_actions.dart` — the long-press actions card: the six USER-locked emoji
  presets + a "+" disc opening the SYSTEM emoji keyboard (first grapheme taken),
  Reply, and Delete. Dims the thread; not a modal.
- `composer.dart` — text input (5000-char compose-time soft cap), the disappearing
  timer preset picker (Off/1min/15min/1hr/24hr; voice string 7 shown VERBATIM), and
  the reply-compose strip. Pings the controller's typing on every keystroke.

No third-party emoji-picker / graph / rich-text dependency — the "+" uses the
platform keyboard (architect pre-rejected those deps).
