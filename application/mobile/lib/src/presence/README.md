# `lib/src/presence` — knock, presence, offline-compose, reconnect (S12)

The presence lane: everything around a live session's *edges* — knocking and
being knocked, the offline-compose outbox, background grace, bounded
live-drop reconnect, and per-channel push opt-in. It consumes the FROZEN
v0.2.1 codec and the S10 connection lane (`../session/connection`) verbatim —
no envelope changes.

## Doctrines this lane enforces
- **Cold knock is never auto-retried** (spec §4, string 6). `KnockController`
  sends ONE knock, waits 60 s, then settles to **"No answer."** + a *manual*
  "Knock again". Only `ReconnectCoordinator` re-knocks, and only to recover a
  session that was already **live** (a distinct doctrine, USER 2026-07).
- **Attribution-free lapse** (DECISIONS 2026-07-04). The knocker renders only
  "No answer." — offline vs saw-and-ignored is indistinguishable. The §6.1
  stale-knock hint is a LOCAL heuristic (repeated unanswered knocks); no wire
  signal, no relay involvement.
- **Ignore is silence** (F6). Ignoring an incoming knock records nothing and
  sends no wire signal; the relay expires the pending knock at 60 s.
- **Background grace is client-only** (spec §3.3). A ~30 s timer, no relay
  state, no VoIP/background-audio socket extension. On expiry the session is
  disposed (socket close = implicit TEARDOWN, §5.4); re-entry is a fresh
  knock, never a resumed session (keys die per session, §3.3.1).
- **Push is opt-IN, DEFAULT OFF** (spec §3.2.1). Off = pure burner-line mode,
  zero third-party touch — an empty KNOCK payload. On = the peer's stored
  token rides inside the KNOCK only; the relay uses it once and forgets it.

## Files
| File | Lane | Responsibility |
|---|---|---|
| `session_launcher.dart` | pure Dart | Builds a `SessionController` from a stored channel — the app's single construction point (chat + reconnect both go through it). Wires the KNOCK push payload and the receive-side token-refresh sink; seeds offline reactions across a reconnect rebuild. **S15**: the optional `onSessionBound` hook (a bare typedef — presence never imports the push lane) lets `PushService.bindSession` announce THIS device's own token on every launched session — wired at the composition root (`bootstrapNimna`, exposed via `NimnaServices.sessionLauncher`). **S16**: threads the per-channel `typingEnabled` (default ON) + `readReceiptsOptIn` (default OFF) F7 preferences from the record into the `SessionController`. |
| `knock_controller.dart` | `ChangeNotifier` | Outgoing knock/waiting/lapse UX (F5): 60 s window, "No answer." + manual "Knock again", §6.1 stale hint. Never auto-retries. |
| `incoming_knock_controller.dart` | `ChangeNotifier` | Receiving-knock banner (F6): "{label} is knocking." + Pick up / Ignore, 60 s auto-dismiss. |
| `reconnect_coordinator.dart` | pure Dart | Bounded (~20 s) automatic recovery of a LIVE-session drop — a fresh knock+KK via the launcher, `ReconnectBackoff`-spaced; reconnecting → recovered / lost. |
| `background_grace.dart` | pure Dart | The ~30 s grace timer (injectable clock): start-on-background, cancel-on-foreground, dispose-session-on-expiry. |
| `app_lifecycle_gate.dart` | **Flutter** | The only WidgetsBinding-coupled file: maps `paused`/`resumed`/`hidden` → grace start/cancel. |
| `push_opt_in.dart` | pure Dart | Per-channel opt-in flag persistence + builds the §5.4 KNOCK payload from the stored peer token when on. |
| `push_opt_in_tile.dart` | **Flutter** | The F7 toggle row + string-18 always-visible disclosure (leaf widget; the mount surface wires it to `push_opt_in`). |
| `peer_token_store.dart` | pure Dart | Receive-side: persists a peer token-refresh CONTROL to the channel record (present→store, absent→revoke). Also names the `SendTokenRefresh` seam S15 fulfils. |

## S12 ⟂ S15 boundary
S12 owns: the opt-in flag UI + persistence, the honest copy, building the
token-into-KNOCK payload, the token-refresh **receive-and-persist** path, the
`SessionController.sendTokenRefresh` **seam** (wire path), and the
platform-preservation invariant (`peerDeviceToken` = §5.7 present-form bytes).
S15 owns: acquiring THIS device's own APNs/FCM token and CALLING
`sendTokenRefresh` with it, plus push-tap → app-launch → reconnect routing.
**No push SDK is added in S12.** Real push delivery, OS backgrounding, and the
push→knock-screen route are device-deferred (S15/S18).
