# SESSION 11 — Media & documents (worktree `session-11-media`)

Group G4 (∥ S12). Consumes the FROZEN v0.2.1 codec (S10) — no envelope changes.
Owns: `lib/src/media` (attach, compression, EXIF strip, MEDIA_CHUNK, viewer,
quarantine) + composer/bubble files inside `lib/src/session/chat`.

Spec: `docs/nimna-protocol-spec-v0.2.1.md` §5 media surface, §5.3 media rules.
Plan: `nimna-build-plan-v3-sessions.md` Session 11.

Done-when: photo and PDF round-trip between devices; EXIF verifiably stripped;
media absent from gallery/photo backups; expired media vanishes on both ends.

---

## Intake

**Author:** tech-architect · **2026-07-07** · Binding for S11 implementation.
Sources: spec §3.4, §5, §5.1, §5.3, §5.4–§5.8; build-plan Session 11 + row
S11/S12 + G4; `docs/architecture/app-architecture.md` §2–§7 (esp. §5 media
store); the FROZEN S10 codec (`lib/src/protocol/inner_envelope.dart`); the S7
storage foundation (`MediaRepository`, `MediaStore`, `media_ix`); designs
(`components.md` media bubbles / viewer / attach / quote; `tokens.json` media
block; voice strings 7/14/15/17/20). All CODE unless marked USER.

Ground truth discovered — much of S11's substrate already exists and is
reused, not rebuilt:
- The **codec is complete and frozen**: `InnerType.mediaChunk`,
  `ManifestBody` (`chunk_count(4)‖total_len(8)‖content_hash(32)‖mime_len(1)‖
  mime`), `ChunkBody` (`manifest_msg_id(16)‖chunk_index(4)‖chunk_data`),
  manifest `expiry_s`/`reply_to` flags — all present, vector-locked, byte-
  identical to Go. **S11 consumes it verbatim; zero envelope change.**
- The **at-rest media layer is built (S7):** `MediaRepository.add()` writes an
  AEAD blob file (CDK-derived key, storeId 0x04) + an encrypted `media_ix`
  record and **already computes `SHA-256` content_hash** over the exact
  bytes; `media_ix` plaintext columns are only `id/channel_id/purge_at`
  (mime/len/hash/msgId live inside `MediaIndexRecord` ciphertext). Blobs live
  under the backup-excluded store root, never gallery/Documents/tmp.
- `MessageRecord` already carries `type: media`, `mediaId`; `MessageView` /
  `ReplyReferentKind` already model photo/document; the composer + bubble +
  session_controller already carry explicit `TODO(S11)` seams.

### 1. Module layout & file-disjointness from S12

**New tree `lib/src/media/` (all S11-owned):**

- `model/media_attachment.dart` — value type for a picked+processed
  attachment (bytes, mime, pixel dims, originalQuality flag). Flutter-free.
- `model/media_transfer_state.dart` — bubble transfer state
  (sending/receiving/loaded/failed + 0..1 progress). Flutter-free.
- `transfer/media_chunker.dart` — pure: attachment plaintext → one
  `ManifestBody` + ordered `ChunkBody` envelopes using the FROZEN codec
  (65,536-B chunks, last short; `chunk_count = ceil(total_len/65536)`).
  Flutter-free.
- `transfer/media_reassembler.dart` — pure: per-transfer buffer keyed by
  `manifest_msg_id`; collects chunks by index, verifies `SHA-256 ==
  content_hash` (reuses `package:crypto`), signals complete / mismatch /
  incomplete. Flutter-free.
- `transfer/media_transfer_controller.dart` — pure orchestrator the session
  delegates to: outbound (chunk → session seal callback + progress), inbound
  (valid MEDIA_CHUNK env → reassembler → on success persist via
  `MediaRepository` + ACK callback; on mismatch/incomplete → discard, NO
  ACK). **Flutter-free by construction** so the connection lane may hold a
  reference without breaking the import-direction fence.
- `pipeline/image_processor.dart` — EXIF strip + compression via
  `package:image`, run in `Isolate.run` (dart:isolate). Flutter-free.
- `pipeline/attachment_picker.dart` — `file_picker` wrapper (photo/file,
  5 MB cap check, mime derivation). Flutter-coupled — NOT reachable from the
  connection lane.
- `pipeline/media_export.dart` — `share_plus` decrypt-to-temp export +
  immediate cleanup (the one deliberate quarantine exit). Flutter-coupled.
- `ui/attach_sheet.dart` — attach bottom sheet + preview (original-quality
  toggle off by default, metadata-strip notice string 17, over-cap error
  string 17).
- `ui/media_bubble_content.dart` — the media bubble body (image edge-to-edge
  / document row / sending+receiving 2 px progress line). Consumed BY
  `message_bubble.dart` through a content hook (S11 renders only up to the
  loaded state; the S14 sensitive-blur veil layers ON TOP later).
- `ui/media_viewer.dart` — full-bleed viewer + Export bar (components.md).

**Session files S11 touches (`lib/src/session/chat`, S11's lane — clean vs
S12's `session/connection`):**
- `chat/composer.dart` — add the plus/attach affordance left of the input
  (opens `attach_sheet`); resolve the existing `TODO(S11)` photo-vs-document
  reply-strip label.
- `chat/message_bubble.dart` — branch on `MessageType.media` to render
  `media_bubble_content`; wire long-press eligibility for media manifests;
  the quote block already handles photo/document referents.
- `chat/chat_screen.dart` — wire attach → send-media; push the media viewer
  on image/doc tap.
- `chat/message_actions.dart` — no change expected (already media-agnostic;
  operates on `MessageView`).

**Shared-surface risks (flagged — the crux of G4):**

1. **`session/connection/session_controller.dart` — PRIMARY MERGE HOTSPOT
   (both S11 and S12 must edit it).** The build plan itself seeded a
   `TODO(S11)` here (the `case mediaChunk:` dispatch) *and* a dozen
   `TODO(S12)` seams (start/knock/outbox/reconnect). Media send+receive
   physically requires the transport+counters+header this file owns; there
   is no way to ride media without touching it. S11's edit is kept **minimal
   and region-localised** to media-only regions, disjoint from S12's:
   (a) replace the `case mediaChunk:` TODO with `_media?.onInbound(env)`;
   (b) add post-construction `void attachMedia(MediaTransferController)` +
   nullable `_media` field; (c) add `bool sealMediaFrame(InnerEnvelope) =>
   _seal(env)` and a public `sendMedia(...)` entry that drives the chunker.
   No Flutter import is added (fence holds); `MediaTransferController` is
   Flutter-free. **Resolution rule (pre-authorised, CLAUDE.md G4):** treat
   this file as a serialization point — **S11's media hooks land first,
   S12 rebases**; on a same-file conflict twice, drop G4 to serial S11→S12
   and note in PROGRESS. This is the single biggest coordination item; it is
   a CODE/sequencing matter, not a USER question.
2. **`session/model/` — secondary hotspot (different files, likely merge-
   clean).** S11 edits `model/message_view.dart` (add media fields: mime,
   byteLength, transfer state; change `isReferentEligible` to also accept
   media manifests). S12 edits `model/chat_event.dart` (add
   knocking/waiting/lapsed `SessionLineState`s). Different files under
   `model/` — 3-way merge should succeed; flagged so QA watches it.
3. **`lib/src/diag/diag_events.dart` — low-risk shared (append-only enums).**
   S11 adds media diag events (`mediaTransferComplete`, `mediaHashMismatch`,
   `mediaExpired`); S12 adds knock/reconnect events. Enum-append merges are
   normally clean; namespaced, region-adjacent.
4. **`lib/src/app/routes.dart` — AVOIDED.** The media viewer is pushed via an
   on-the-fly `NimnaPageRoute` from the bubble tap (no named route), so
   `routes.dart` is NOT edited by S11 (see §6). Keeps this shared app/ file
   untouched.

`session/chat` (S11) vs `session/connection` (S12) is otherwise fully
disjoint. The `import_direction_test` fence stays green: connection/ imports
no Flutter (the media types it references are Flutter-free); chat/ holds no
transport/keys/store.

### 2. Dependency decisions

Only **one new dependency** is proposed; everything else reuses S7–S9 deps.

- **`image` (pub.dev, Brendan Duncan) — proposed pin `^4.5.4` (exact resolved
  version recorded in pubspec.lock at pin time) — SIGN-OFF GIVEN, conditional
  on the standing pin-time audit passing.** Purpose: on-device image
  decode → EXIF/metadata strip → re-encode (compression). **100% on-device
  and network-incapable by construction** — it is pure Dart with no platform
  channel and no socket API, so "zero network calls" is structural, not a
  configuration we must trust. EXIF strip is likewise structural: decoding to
  a pixel buffer and re-encoding cannot carry the EXIF APP1 segment; we
  additionally `bakeOrientation` so stripping the orientation tag does not
  rotate the image. Runs inside `Isolate.run` to keep the 5 MB worst case off
  the UI isolate. **Required pin-time audit (standing gate):** `flutter pub
  deps` + grep the transitive tree for `analytics|firebase|crashlytics|
  sentry|beacon|http|dio|socket` — expect CLEAN (the package's only
  transitives are pure-Dart codec/math helpers, e.g. `archive`, `meta`); the
  developer records the audit result in `## Deps added` before merge. Fence:
  used ONLY from `lib/src/media/pipeline/image_processor.dart`.
  - **Rejected `flutter_image_compress`:** native libjpeg/libwebp plugin —
    adds a second image-codec native surface and its EXIF handling is a
    re-encode side-effect rather than an auditable pure-Dart guarantee; under
    the 5 MB cap the pure-Dart path is fast enough. Boring/on-device/
    auditable doctrine picks `image`.
  - **Rejected `image_picker` / `camera`:** designs specify the attach source
    as "photo / file pickers" (components.md attach affordance + attach
    sheet), which `file_picker` already covers. No camera-capture attach path
    is in the designs — see §7.

**Reused, no re-add, no new sign-off (already in tree + audited):**
- **`file_picker` 11.0.2 (S9)** — photo + file attach (`FileType.image` /
  `FileType.custom` pdf). Second call site added
  (`media/pipeline/attachment_picker.dart`); the existing S9 fence comment is
  updated to name both sites.
- **`share_plus` 13.2.0 (S8)** — media Export (decrypt-to-temp → share →
  cleanup). Second call site (`media/pipeline/media_export.dart`).
- **`crypto` 3.0.7 (S2/S7)** — `SHA-256` content_hash for manifest + reassembly
  verification. Already used by `MediaRepository`; reused in the reassembler.
- **`pdfrx` 2.4.4 (S9)** — available if an in-app PDF first-page thumbnail is
  wanted; **not required** — the document bubble/quote render a doc glyph, and
  the viewer offers Export/open (see §7). No new use unless a thumbnail is
  chosen; if used, it is the SAME already-audited local-rasterize path.
- **No `mime` package:** MIME is derived from the picked extension via a small
  in-repo const map over the allowed types (jpeg/png/webp/gif/pdf) — stdlib-
  first, no dependency.

### 3. Codec-consumption contract (FROZEN — no envelope change)

S11 consumes the S10 codec byte-for-byte and adds NO wire behavior:
- **Manifest** (`type=MEDIA_CHUNK`, flags bit 1): body decoded by
  `ManifestBody` = `chunk_count(4)‖total_len(8)‖content_hash(32)‖mime_len(1)‖
  mime`. `content_hash` = `SHA-256` of the complete post-compress/post-strip
  attachment plaintext (the exact bytes `MediaRepository.add()` already
  hashes). Manifest may carry `expiry_s` (bit 0) and `reply_to` (bit 2) — both
  already codec-supported; chunks carry neither.
- **Chunk** (flags bit 1 clear): `ChunkBody` = `manifest_msg_id(16)‖
  chunk_index(4)‖chunk_data`. Plaintext 65,536 B for every chunk but the last;
  `chunk_count ≤ 80` at the 5 MB cap. 65,536-B chunk + AEAD tag + 18-B outer
  header sits comfortably inside the relay's 128 KiB frame cap (§4).
- **Reassembly & ACK ride the existing transport unchanged.** Receiver
  buffers chunks by index under `manifest_msg_id`, and on completeness
  verifies `SHA-256 == content_hash`, then **ACKs the manifest `msg_id`**
  (spec §5.1, §3.3) — reusing the exact ACK path `_onInboundText` already
  uses. To the relay these are opaque frames; no relay-side reassembly.
- **Error taxonomy (must be exact):** a *structurally* malformed MEDIA_CHUNK
  frame (body < fixed size, mime_len mismatch) throws `InnerEnvelopeError` in
  the codec → the existing `_onSessionData` path already treats that as a
  §3.3.1 protocol error (destroy keys + TEARDOWN). A *transfer-level* failure
  on structurally-valid frames — hash mismatch, missing/duplicate/out-of-range
  chunk index, chunk before manifest — is **discard the transfer + NO ACK,
  never a protocol error** (spec §5.1: "a resend is the sender's call"). The
  reassembler enforces this line; the session-kill path is never taken for a
  transfer-integrity failure.
- A received manifest becomes a **reactable/replyable referent** (spec §5.8):
  `MessageView.isReferentEligible` is widened to include media manifests, and
  `_resolveReply` distinguishes photo vs document from the persisted mime.

### 4. At-rest + privacy invariants (all ride S7; confirmed)

- **EXIF strip happens in `image_processor` BEFORE encryption** — the stripped
  + compressed plaintext is what `MediaRepository.add()` hashes and AEAD-seals.
  content_hash therefore covers exactly the transmitted bytes (manifest match
  guaranteed).
- **Quarantine:** blobs are written ONLY to `<root>/media/<hex(id)>` via
  `MediaStore` (CDK-derived AEAD, storeId 0x04). Never gallery, Documents, or
  tmp. Display decrypts to memory. Export is the one deliberate exit
  (decrypt-to-temp → share sheet → immediate temp cleanup). A fence test
  asserts `lib/src/media` imports no gallery/photo-save API.
- **Backup exclusion:** the media dir is under the store root already
  `isExcludedFromBackup` / `dataExtractionRules`-excluded at S7 — media
  inherits it; no new mechanism.
- **Plaintext-budget impact: NONE beyond the existing budget.** `media_ix`
  keeps only `id/channel_id/purge_at` (surrogates + int); mime, byte length,
  content_hash, msg_id all stay inside `MediaIndexRecord` ciphertext. The
  message row for a media message reuses the existing columns
  (`id/channel_id/seq/purge_at/ct`) with `type=media` + `mediaId` inside ct.
- **Expiry applies to media identically to text (spec §5.1).** Manifest
  `expiry_s` → the media message record's `expiry_s`; read-at = display time
  (receiver) / compose time (sender, "yours will too"); `purge_at =
  read_at + expiry_s*1000` is mirrored to BOTH the message row and the
  `media_ix` row plaintext column (already the accepted, disclosed leak). The
  purge sweep for media MUST delete the `media_ix` row **and its blob file**
  (via `MediaRepository.delete`) alongside the message row, on both ends —
  S11 owns extending whatever expiry-purge sweep the message layer uses to
  cover the blob; if no shared sweep exists yet, S11 adds the media purge and
  QA verifies it against the text-expiry mechanism.

### 5. Done-check plan (headless-provable vs deferred)

| Done-when clause | Evidence (senior-qa, headless) | Deferred |
|---|---|---|
| photo + PDF round-trip between devices | Integration test wiring two `SessionController`s over `test/helpers/fake_relay.dart` (the S10 live-text harness): send a JPEG + a PDF; assert manifest+chunks reassemble, `SHA-256==content_hash`, manifest ACK fires, and the receiver's decrypted blob == the sender's post-strip plaintext. Go relay forwards opaque frames (S6) — no cross-stack codec work. | Two physical phones = S18 real-device rung (S7/S18 pattern). |
| EXIF verifiably stripped | Unit test: a JPEG fixture with known EXIF (GPS/make/DateTime) → `image_processor` → assert output has NO EXIF/APP1 and pixels preserved with orientation baked. | — (fully headless) |
| media absent from gallery/photo backups | (a) fence test: `lib/src/media` imports no gallery/photo-roll save API; (b) blob writes only under the store root media dir; (c) the store-root backup-exclusion mechanism (isExcludedFromBackup / dataExtractionRules) proven at S7 covers the media dir. | Real gallery/backup forensic inspection = S18 (mirrors S7 §7 deferral). |
| expired media vanishes on both ends | Integration test with injectable clock: send media with `expiry_s`; advance past `purge_at`; assert the purge deletes the `media_ix` row + blob file + message row on BOTH sender and receiver controllers. | — (headless, injectable clock) |

### 6. Route registrations

**No named route added.** The media viewer is pushed on-the-fly from the
bubble tap via `NimnaPageRoute(builder: (_) => MediaViewer(...))`, keeping
`lib/src/app/routes.dart` untouched (avoids a shared app/ file edit). If the
orchestrator prefers a named route for consistency, the alternative to fold
in is `Routes.mediaViewer = '/media'` in `routes.dart` — flagged here, not
taken by default.

### 7. Consolidated USER questions

**None blocking — spec + designs are sufficient.** Two items recorded as CODE
decisions within existing design rails (contestable, not escalated):
- **Compression default parameters** (CODE): within the designs' "compression
  by default, original-quality toggle off by default" rail, S11 targets a
  sensible default (re-encode JPEG ~quality 82, longest-edge cap ~2048 px,
  always ≤ 5 MB); "original quality" strips EXIF but skips down-scale/re-
  compress. Tunable; recorded so it is contestable, not a USER blocker.
- **Camera-capture attach source** (scope — resolved by designs, flagged to
  PM only): components.md specifies the attach source as *photo / file
  pickers*; no camera-capture path is designed. S11 follows the designs (no
  camera). If the PM/USER later wants in-session camera capture, that is a
  scope addition (and a new `image_picker`/`camera` dependency) to raise
  then — NOT taken now.

## Implementation

**Developer:** mobile-developer-flutter · **2026-07-07** · Built to the binding
intake. Analyze / test / format all GREEN (369 tests, 25 net-new in
`test/media/`). Consumes the FROZEN v0.2.1 codec byte-for-byte — ZERO change to
`lib/src/protocol` envelope encode/decode.

**New tree `lib/src/media/` (all S11-owned):**
- `model/media_attachment.dart`, `model/media_transfer_state.dart` — Flutter-free
  leaf value types.
- `transfer/media_chunker.dart` — attachment → manifest + ordered chunk
  envelopes (65,536-B chunks, `chunk_count = ceil(total_len/65536)`, SHA-256
  content hash); consumes the frozen `ManifestBody`/`ChunkBody`/`InnerEnvelope`.
- `transfer/media_reassembler.dart` — per-transfer buffers keyed by
  `manifest_msg_id`; hash-verifies on completeness; **discard + NO ACK** on any
  transfer-integrity failure (hash/length mismatch, out-of-range/duplicate
  index, chunk-before-manifest) — never a protocol error.
- `transfer/media_transfer_controller.dart` — the Flutter-free orchestrator the
  session delegates to: `persistOutgoing`, `transmit`, `onInbound`, `readMedia`,
  `loadIndex`, `purgeExpired`.
- `pipeline/image_processor.dart` — THE `package:image` site: decode →
  `bakeOrientation` → clear `ExifData` → (compress path) downscale → re-encode,
  in `Isolate.run`. `pipeline/media_mime.dart` (in-repo MIME map, no `mime`
  dep), `pipeline/attachment_picker.dart` (2nd `file_picker` site),
  `pipeline/media_export.dart` (2nd `share_plus` site, decrypt-to-temp→share→
  cleanup).
- `ui/media_bubble_content.dart`, `ui/attach_sheet.dart`, `ui/media_viewer.dart`
  — BINDING to components.md media block + tokens.json media block.
- `README.md` per folder.

**Chat lane (`lib/src/session/chat`, S11's lane):** `composer.dart` (attach plus
affordance left of the input; resolved the `TODO(S11)` reply-strip photo-vs-doc
label), `message_bubble.dart` (media branch → `MediaBubbleContent`; media is now
long-press-eligible), `chat_screen.dart` (attach→`sendMedia`, tap→viewer,
export). No `message_actions.dart` change (already media-agnostic).

**Controller edit (kept minimal + media-only, no Flutter import):**
`session/connection/session_controller.dart` gained a nullable `_media` field +
`attachMedia(MediaTransferController)` + `sealMediaFrame` + `sendMedia` +
`ingestReceivedMedia` + `purgeExpiredMedia`; the `case mediaChunk:` TODO became
`_media?.onInbound(env)`; `_resolveReply` distinguishes photo/document from the
persisted mime; `_view` fills the media fields; `_loadHistory` hydrates
mime/len from `media_ix` (media-gated); `_destroyKeys` drops partial transfers.
A private `_MediaMeta` + two maps hold display metadata so the render path stays
synchronous. **`chat_event.dart` was deliberately NOT touched** (the S12
hotspot): media transfer has no new event type — rebuilds ride the existing
`MessageArrived`/`DeliveryChanged`, and the progress line renders
indeterminately.

**Model:** `session/model/message_view.dart` gained `mediaId/mediaMime/
mediaByteLength/mediaTransfer` + `isMedia`/`isMediaImage`; `isReferentEligible`
now includes media manifests (spec §5.8).

**Domain:** added `MediaRepository.purgeExpired(channelId, nowMs)` (media-domain,
S12-disjoint) — no shared expiry sweep existed, so S11 added the media purge:
deletes each due `media_ix` row + blob file and returns the purged `msg_id`s so
the session drops the matching message rows (both ends; injectable-clock test).

**Privacy invariants held:** EXIF strip is structural + verified absent post-strip
(unit test); media rides S7 `MediaRepository` AEAD blobs (never gallery — fence);
plaintext budget unchanged (mime/len/hash stay in `media_ix` ciphertext); expiry
applies to media on both ends. `package:image` is pure-Dart, network-incapable
by construction (fenced to one site).

## Decisions (fold candidates — USER vs CODE)

- **CODE (2026-07-07, architect intake):** S11 adds exactly ONE new
  dependency — `image` (^4.5.4, pure Dart) for on-device EXIF-strip +
  compression. `flutter_image_compress` and `image_picker`/`camera` rejected.
  All other media needs reuse S7–S9 deps (`file_picker`, `share_plus`,
  `crypto`, optionally `pdfrx`). No `mime` package (in-repo extension map).
- **CODE (2026-07-07):** media send/receive integrate through a **minimal,
  region-localised edit to `session/connection/session_controller.dart`** (a
  connection-lane file both S11 and S12 must touch). S11's media hooks land
  first and S12 rebases; on a twice-repeated same-file conflict, G4 drops to
  serial S11→S12 per the CLAUDE.md churn rule. Flagged as the primary G4
  merge hotspot; `session/model/` (message_view.dart vs chat_event.dart) and
  `diag/diag_events.dart` are secondary, expected-clean shared surfaces.
- **CODE (2026-07-07):** `MessageView.isReferentEligible` widens to include
  media manifests (spec §5.8 makes a manifest a reactable/replyable referent).
- **CODE (2026-07-07):** transfer-integrity failures (hash mismatch, missing/
  duplicate/out-of-range chunk) = discard + NO ACK, NEVER a §3.3.1 protocol
  error (spec §5.1); only structural codec errors kill the session.
- **CODE (2026-07-07):** media viewer pushed as an on-the-fly route, no
  `routes.dart` edit.
- **CODE (2026-07-07):** compression default = re-encode JPEG ~q82, longest-
  edge cap ~2048 px, always ≤ 5 MB; original-quality path strips EXIF but
  skips downscale/recompress. Contestable parameter, not USER-blocking.
- **USER questions: NONE.** Camera-capture attach is out of scope per designs
  (photo/file pickers only); flagged to PM only, not escalated.

Developer-added (2026-07-07, all CODE, within intake rails):
- **CODE:** `chat_event.dart` (the S12 merge hotspot) was NOT edited — media
  transfer introduces no new `ChatEvent` subtype; the sender's sending overlay
  + the receiver's completion ride existing `MessageArrived`/`DeliveryChanged`
  emissions, and the 2 px progress line renders indeterminately (design:
  "reassurance, not a meter"). Keeps the G4 fold clean.
- **CODE:** the media expiry sweep lives on `MediaRepository.purgeExpired` +
  `SessionController.purgeExpiredMedia` (media-domain files, disjoint from S12).
  No shared text-expiry sweep exists yet, so S11 added the media one; QA can
  verify it against the text `purge_at` mechanism. Production scheduling of the
  sweep is a later lane; the injectable-clock done-check drives it explicitly.
- **CODE:** re-encode container policy — opaque images → JPEG, alpha images →
  PNG; webp/gif inputs are re-encoded (their EXIF cannot survive), so the
  OUTPUT mime (what the manifest carries) is returned by the processor, not the
  picked extension. "Original quality" re-encodes at JPEG q100 without
  downscale (surgical APP1 removal without recompress is deferred, noted as
  contestable).
- **CODE:** receiver renders the media bubble on transfer COMPLETION (loaded);
  the mid-transfer "Receiving" placeholder state is modeled + supported by the
  bubble but not yet driven on the receive path (transfers are seconds; no
  pre-record before the blob exists). Follow-up flagged, not blocking.
- **CODE:** the `share_plus` single-call-site fence
  (`test/pairing/single_call_site_test.dart`) now allows a SECOND site,
  `media/pipeline/media_export.dart`, per the intake §2 export sign-off.

## Deps added (architect sign-off required)

- **`image: ^4.5.4`** (pub.dev, Brendan Duncan) — pure-Dart image decode /
  EXIF-strip / re-encode; on-device + network-incapable by construction.
  **SIGN-OFF GIVEN**, conditional on the standing pin-time no-telemetry audit.
  Fence: ONLY `lib/src/media/pipeline/image_processor.dart`, run in
  `Isolate.run`. Runtime dep, caret-pinned; exact resolved version committed
  via pubspec.lock.
  - **Pin-time audit checklist (developer completes before merge, records
    result here):** `flutter pub deps` tree grepped for
    `analytics|firebase|crashlytics|sentry|beacon|http|dio|socket` → expect
    CLEAN; confirm no platform channel / no dart:io socket usage; record the
    exact resolved version + transitive list.
  - **`[x] AUDIT RESULT (2026-07-07, developer): CLEAN.`** Resolved
    `image 4.8.0` (caret `^4.5.4`; exact version in pubspec.lock). Its
    transitive tree is `archive 4.0.9`, `xml 6.6.1` (→ `petitparser 7.0.2`,
    `collection`), `meta` — all pure-Dart codec/parse/math helpers. The
    `analytics|firebase|crashlytics|sentry|beacon|dio|socket` grep over the
    `image` subtree = no matches; no platform channel, no `dart:io` socket. (A
    pre-existing `http 1.6.0` appears in the WIDER app tree from
    share_plus/in_app_purchase — NOT under `image`.) `image` was already a
    transitive dep, now promoted to direct; fenced to
    `lib/src/media/pipeline/image_processor.dart` (media_fences_test).
- Reused (no re-add / no new sign-off): `file_picker` 11.0.2, `share_plus`
  13.2.0, `crypto` 3.0.7, (optionally) `pdfrx` 2.4.4 — each gains one new
  fenced call site under `lib/src/media`; update the existing fence comments
  to name the added site.

## ARB keys added (namespaced `media_*` / `chat_*`)

Reused (already present, S10): `chat_replyPreviewPhoto` ("Photo"),
`chat_replyPreviewDocument` ("Document"). New keys (canonical microcopy from
the voice guide — no invention; DE/FR/ES/IT filled at S16 per the l10n
stance):
- `media_attachA11y` — attach affordance a11y label.
- `media_pickPhoto` / `media_pickFile` — attach sheet options.
- `media_overCapError` — voice string 17 ("That's over 5 MB — the line
  carries documents, not archives. Try a smaller file.").
- `media_metadataStripNotice` — voice string 17 ("Photos are cleaned before
  they're sealed — location, device, and time are stripped on your phone,
  before encryption.").
- `media_originalQualityToggle` — attach-preview toggle label.
- `media_exportAction` / `media_exportConfirm` — viewer Export + confirm sheet
  ("This copies it out of Nimna — into your phone's own storage." / string 16
  "Nothing you receive touches your photo roll…").
- `media_viewerReceivedTime` — viewer top-bar received-time label.
- `media_sendingA11y` / `media_receivingA11y` / `media_documentA11y` — bubble
  state a11y labels.
- (Sensitive-content blur/whisper strings 14/15 are **S14's** namespace, not
  added here.)

**Actually added (2026-07-07, EN canonical only in `app_en.arb`; DE/FR/ES/IT
stay locale-only stubs → S16, matching how S10 handled non-EN):** 21 keys, all
`media_*` — `media_attachA11y`, `media_pickPhoto`, `media_pickFile`,
`media_overCapError` (string 17 verbatim), `media_metadataStripNotice` (string
17 verbatim), `media_compressionNote` (string 17 verbatim),
`media_originalQualityToggle`, `media_exportAction`, `media_exportConfirm`
(components.md verbatim), `media_exportRollNote` (string 16/17 verbatim),
`media_exportCancel`, `media_viewerReceivedTime` (`{time}`), `media_sendingA11y`,
`media_receivingA11y`, `media_documentA11y`, `media_imageA11y`,
`media_documentKindPdf`, `media_documentKindFile`, `media_sizeMegabytes`
(`{size}`), `media_sizeKilobytes` (`{size}`), `media_documentMeta`
(`{kind}·{size}`). The last five are factual UI labels (file type / size)
required by the components.md doc-row, not voice-guide marketing strings — noted
for the S16 pass. Reused from S10: `chat_replyPreviewPhoto/Document`,
`chat_sendA11y`. No namespace collision with any other session.

## Route registrations

**None** — the media viewer is pushed via an on-the-fly `NimnaPageRoute` from
the bubble tap; `lib/src/app/routes.dart` is intentionally NOT edited. (Optional
alternative for the orchestrator, not taken: `Routes.mediaViewer = '/media'`.)

## Review

## QA done-check

## Next / follow-ups

- **Fold-time coordination (G4):** `session_controller.dart` is the primary
  hotspot — S11's media hooks are region-localised (a `_media` field,
  `attachMedia`/`sealMediaFrame`/`sendMedia`/`ingestReceivedMedia`/
  `purgeExpiredMedia`, the `case mediaChunk:` line, and small additions in
  `_resolveReply`/`_view`/`_loadHistory`/`_destroyKeys`) and add NO Flutter
  import. `chat_event.dart` was intentionally left untouched so S12 owns it
  outright. `diag_events.dart` gained ids 19/20/21 (`mediaTransferComplete`,
  `mediaHashMismatch`, `mediaExpired`) — S12 continues from 22. `message_view.dart`
  (S11) vs `chat_event.dart` (S12) are different `model/` files → clean 3-way.
- **Device-deferred rungs (S7/S18 pattern, implemented fully, not faked):** the
  real photo/file picker + camera, the OS share sheet, and real
  gallery/backup/EXIF forensic inspection. Headless coverage stands in via the
  fences + the integration harness.
- **Deferred nicety:** receiver mid-transfer "Receiving" placeholder bubble
  (record currently created on completion). Purge-sweep production scheduling
  (a lifecycle owner) is a later lane; the manual `purgeExpiredMedia()` +
  injectable clock prove it now.
- **Contestable CODE params:** compression q82 / 2048 px longest edge;
  original-quality = q100 no-downscale (surgical APP1 removal deferred).
