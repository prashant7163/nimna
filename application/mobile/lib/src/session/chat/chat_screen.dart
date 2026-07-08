/// The chat screen (S11 lane seed) — it WIRES a [SessionController] to the
/// composer, bubbles, and message-actions card, and renders the session-status
/// line. NO protocol logic lives here: it reads the controller's immutable
/// [SessionController.messages] / [SessionController.lineState] /
/// [SessionController.peerTyping] and forwards user intent to the controller's
/// typed send methods. BINDING to `designs/system/components.md` (chat header,
/// session-status-indicator) and wireframe F5.
///
/// The rich presence choreography (knocking/waiting/lapse, reconnect) is S12;
/// S10 renders the minimal line states this session produces.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app/transitions.dart';
import '../../media/pipeline/media_export.dart';
import '../../media/ui/attach_sheet.dart';
import '../../media/ui/media_viewer.dart';
import '../../presence/reconnect_coordinator.dart' show ReconnectPhase;
import '../../screenshot/screenshot_detector.dart';
import '../../screenshot/screenshot_notice.dart';
import '../../screenshot/screenshot_system_line.dart';
import '../../sensitive/sensitive_content_analyzer.dart';
import '../../ui/theme/nimna_tokens.dart';
import '../../ui/widgets/glyphs.dart';
import '../connection/session_controller.dart';
import '../model/chat_event.dart';
import '../model/message_view.dart';
import 'composer.dart';
import 'message_actions.dart';
import 'message_bubble.dart';

/// Route arguments for the chat screen — the built session and the channel's
/// local label. The entry points that construct the controller (channel-row
/// tap / incoming-knock pick-up) are S12's; S10 provides the screen + route.
class ChatScreenArgs {
  const ChatScreenArgs({required this.controller, required this.label});

  final SessionController controller;
  final String label;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.controller,
    required this.label,
    this.screenshotDetector,
    this.sensitiveAnalyzer,
    this.onKnock,
    this.knockDeadline,
    this.knockLapsed = false,
    this.knockStaleHint = false,
    this.reconnectPhase,
    this.autoStart = true,
    super.key,
  });

  final SessionController controller;
  final String label;

  /// S16 presence choreography (all optional; a bare ChatScreen renders exactly
  /// as before). The coordinating [LinePresence] wraps this screen and maps the
  /// knock/reconnect controllers → these props. When any is set, the pre-live
  /// surfaces (F5.1 "Not on the line", screen-11 waiting, F5.13 "No answer.")
  /// render; when all are unset/false the live chat renders unchanged.

  /// F5.1/F5.13 — the Knock affordance in the header (voice string, verb
  /// "Knock" / after a lapse "Knock again"). Null when live or when this screen
  /// is used standalone (e.g. the push-tap incoming-knock pick-up path). Its
  /// presence also flags the "compose-while-not-on-the-line" surface (§3.4).
  final VoidCallback? onKnock;

  /// Screen 11 (chat-waiting) — the moment the current knock lapses; drives the
  /// F5 countdown (knock_lapsesInSeconds) and the waiting caption. Null unless a
  /// knock is in flight.
  final DateTime? knockDeadline;

  /// F5.13 — the knock's 60 s window closed unanswered: render "No answer." and
  /// re-label the Knock affordance "Knock again". Never an attribution.
  final bool knockLapsed;

  /// F5.14 — the §6.1 local stale-knock hint after repeated unanswered knocks
  /// (no wire signal, no attribution).
  final bool knockStaleHint;

  /// F5.15 — a LIVE-session drop is auto-recovering; overrides the status line
  /// with the reconnect caption (dropped/recovered/lost). Null/idle otherwise.
  final ReconnectPhase? reconnectPhase;

  /// Whether the screen kicks the connection lane itself on mount. True for the
  /// standalone /chat route (S10); [LinePresence] owns the lifecycle and passes
  /// false so the CRID is never registered on two connections at once.
  final bool autoStart;

  /// S14 (spec §5.2): local screenshot detection. Injected in tests; defaults
  /// to the platform detector. The screen owns its lifecycle — it observes ONLY
  /// while mounted (session content on screen inside the app).
  final ScreenshotDetector? screenshotDetector;

  /// S14 (spec §5.3): on-device sensitive-content analysis for recipient blur
  /// and sender whisper. Injected in tests; defaults to the platform analyzer
  /// (iOS-only, fail-open elsewhere).
  final SensitiveContentAnalyzer? sensitiveAnalyzer;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  StreamSubscription<ChatEvent>? _sub;
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};
  MessageView? _replyingTo;

  late final ScreenshotDetector _detector;
  StreamSubscription<void>? _screenshotSub;
  late final SensitiveContentAnalyzer _analyzer;

  /// A 1 s repaint tick, live ONLY while a knock countdown is on screen
  /// (knockDeadline set) — the same lightweight ticker pattern the knock
  /// screen uses. No timer runs in the steady live/idle chat.
  Timer? _countdownTick;

  @override
  void initState() {
    super.initState();
    _sub = widget.controller.events.listen(_onEvent);
    _syncCountdownTick();
    // Screenshot detection is on ONLY while this screen is mounted — spec
    // §5.2's "detection fires only while content is on screen inside the app".
    _detector = widget.screenshotDetector ?? PlatformScreenshotDetector();
    _analyzer = widget.sensitiveAnalyzer ?? PlatformSensitiveContentAnalyzer();
    _screenshotSub = _detector.onScreenshot.listen((_) {
      // The controller additionally gates on liveness and seals CONTROL 0x03.
      widget.controller.noticeLocalScreenshot();
    });
    unawaited(_detector.start());
    // Kick the live path (register CRID / knock / accept) ONLY when this screen
    // owns the lifecycle (the standalone /chat route, S10). Under [LinePresence]
    // (S16) the coordinator owns start(), so autoStart is false — the CRID is
    // never registered on two connections at once (the one-CRID invariant).
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.controller.lineState == SessionLineState.offline) {
          unawaited(widget.controller.start());
        }
      });
    }
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A reconnect swaps in a FRESH controller (keys die per session, §3.3.1);
    // re-subscribe so the thread follows the live controller. The screen holds
    // no protocol state, so nothing else migrates.
    if (!identical(widget.controller, oldWidget.controller)) {
      _sub?.cancel();
      _sub = widget.controller.events.listen(_onEvent);
    }
    _syncCountdownTick();
  }

  /// Runs a 1 s repaint tick only while a knock countdown is on screen.
  void _syncCountdownTick() {
    final wantTick = widget.knockDeadline != null;
    if (wantTick && _countdownTick == null) {
      _countdownTick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    } else if (!wantTick) {
      _countdownTick?.cancel();
      _countdownTick = null;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _countdownTick?.cancel();
    unawaited(_screenshotSub?.cancel());
    unawaited(_detector.stop());
    unawaited(_detector.dispose());
    _scroll.dispose();
    super.dispose();
  }

  void _onEvent(ChatEvent event) {
    if (!mounted) {
      return;
    }
    setState(() {});
    if (event is MessageArrived || event is ScreenshotNoticed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: NimnaMotion.standard,
        curve: NimnaMotion.easeStandard,
      );
    }
  }

  void _send(String text, int? expirySeconds) {
    final reply = _replyingTo;
    if (reply?.msgId != null) {
      widget.controller.sendReply(
        text,
        reply!.msgId!,
        expirySeconds: expirySeconds,
      );
      setState(() => _replyingTo = null);
    } else {
      widget.controller.sendText(text, expirySeconds: expirySeconds);
    }
  }

  Future<void> _openAttach(int? expirySeconds) async {
    final attachment = await showAttachSheet(
      context,
      sensitiveAnalyzer: _analyzer,
    );
    if (attachment == null) {
      return;
    }
    final reply = _replyingTo;
    unawaited(
      widget.controller.sendMedia(
        attachment,
        expirySeconds: expirySeconds,
        replyTo: reply?.msgId,
      ),
    );
    if (reply != null && mounted) {
      setState(() => _replyingTo = null);
    }
  }

  void _openMediaViewer(MessageView message) {
    final mediaId = message.mediaId;
    if (mediaId == null) {
      return;
    }
    Navigator.of(context).push(
      NimnaPageRoute<void>(
        builder: (_) => MediaViewer(
          loadBytes: () => widget.controller.readMedia(mediaId),
          isImage: message.isMediaImage,
          label: widget.label,
          timestampMs: message.timestampMs,
          onExport: () => _exportMedia(message),
        ),
      ),
    );
  }

  Future<void> _exportMedia(MessageView message) async {
    final mediaId = message.mediaId;
    final mime = message.mediaMime;
    if (mediaId == null || mime == null) {
      return;
    }
    final bytes = await widget.controller.readMedia(mediaId);
    await MediaExport.share(bytes: bytes, mime: mime);
  }

  Future<void> _openActions(MessageView message) async {
    await showMessageActions(
      context,
      message: message,
      onReact: (emoji) {
        if (message.msgId != null) {
          widget.controller.sendReaction(message.msgId!, emoji);
        }
      },
      onRemoveReaction: () {
        if (message.msgId != null) {
          widget.controller.removeReaction(message.msgId!);
        }
      },
      onReply: () => setState(() => _replyingTo = message),
      onDelete: () => widget.controller.deleteMessage(message.recordId),
    );
  }

  void _scrollToReferent(Uint8List recordId) {
    final key = _itemKeys[_hex(recordId)];
    final ctx = key?.currentContext;
    if (ctx != null) {
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          duration: NimnaMotion.standard,
          curve: NimnaMotion.easeStandard,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: tokens.surface0,
      body: SafeArea(
        child: Column(
          children: [
            _header(context, tokens, l10n),
            _presenceBanner(tokens, l10n),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(
                  horizontal: NimnaSpacing.screenMargin,
                  vertical: NimnaSpacing.base * 2,
                ),
                children: _threadChildren(),
              ),
            ),
            Composer(
              onSend: _send,
              onTyping: widget.controller.setTyping,
              onAttach: _openAttach,
              replyingTo: _replyingTo,
              onCancelReply: () => setState(() => _replyingTo = null),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the thread children: message bubbles in the connection lane's
  /// order (never re-sorted), with each screenshot system line interleaved just
  /// AFTER its anchor message (spec §5.2, string 12). A notice anchored to null
  /// leads the thread; one whose anchor was deleted/purged falls to the end.
  /// Whether the coordinator has this screen in a "not on the line" posture
  /// (listening / knocking / lapsed) — the §3.4 compose-while-offline surface.
  bool get _notOnLine =>
      (widget.onKnock != null ||
          widget.knockDeadline != null ||
          widget.knockLapsed) &&
      widget.controller.lineState != SessionLineState.live;

  List<Widget> _threadChildren() {
    final messages = widget.controller.messages;
    // F5.1 — nothing written yet and not on the line: the compose-to-outbox
    // explainer (they're not on the line; anything you write waits on your
    // phone). Only in the plain listening state — the waiting/lapsed banners
    // above already carry their own copy.
    if (_notOnLine &&
        messages.isEmpty &&
        widget.knockDeadline == null &&
        !widget.knockLapsed) {
      return [_peerOfflineEmptyState()];
    }
    final notices = widget.controller.screenshotNotices;
    final present = <String, List<ScreenshotNotice>>{};
    final leading = <ScreenshotNotice>[];
    final trailing = <ScreenshotNotice>[];
    final ids = {for (final m in messages) _hex(m.recordId)};
    for (final n in notices) {
      final anchor = n.anchorRecordId;
      if (anchor == null) {
        leading.add(n);
      } else if (ids.contains(_hex(anchor))) {
        present.putIfAbsent(_hex(anchor), () => []).add(n);
      } else {
        trailing.add(n);
      }
    }
    var sysIndex = 0;
    Widget systemLine(ScreenshotNotice n) => ScreenshotSystemLine(
      key: ValueKey('screenshot-${sysIndex++}'),
      notice: n,
    );

    final children = <Widget>[];
    // F5.1 — the outbox header over messages waiting on your phone while not on
    // the line (spec §3.4, "WAITING — ON YOUR PHONE ONLY").
    if (_notOnLine && messages.isNotEmpty) {
      children.add(_waitingHeader());
    }
    for (final n in leading) {
      children.add(systemLine(n));
    }
    for (final m in messages) {
      children.add(
        KeyedSubtree(
          key: _keyFor(m.recordId),
          child: MessageBubble(
            message: m,
            sensitiveAnalyzer: _analyzer,
            onLongPress: () => unawaited(_openActions(m)),
            onTapQuote: m.reply?.referentRecordId == null
                ? null
                : () => _scrollToReferent(m.reply!.referentRecordId!),
            mediaLoadBytes: m.isMedia && m.mediaId != null
                ? () => widget.controller.readMedia(m.mediaId!)
                : null,
            onTapMedia: m.isMedia ? () => _openMediaViewer(m) : null,
          ),
        ),
      );
      final after = present[_hex(m.recordId)];
      if (after != null) {
        for (final n in after) {
          children.add(systemLine(n));
        }
      }
      // F7 read receipts: a single right-aligned "Seen" caption under the
      // latest sent message the peer has read (spec §5). Only ever present when
      // the PEER opted into receipts; silent otherwise. Never a per-message
      // badge — one caption, iMessage-style.
      final seenAnchor = widget.controller.latestSeenOutboundRecordId;
      if (seenAnchor != null && _hex(seenAnchor) == _hex(m.recordId)) {
        children.add(_seenCaption());
      }
    }
    for (final n in trailing) {
      children.add(systemLine(n));
    }
    if (widget.controller.peerTyping) {
      children.add(const PeerTypingBubble());
    }
    return children;
  }

  /// F5.1 — the empty-thread "not on the line" explainer (compose-to-outbox,
  /// spec §3.4). Centered; every string ARB-sourced.
  Widget _peerOfflineEmptyState() {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NimnaSpacing.base * 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.chat_peerOfflineHeadline,
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(color: tokens.textPrimary),
          ),
          const SizedBox(height: NimnaSpacing.base * 2),
          Text(
            l10n.chat_peerOfflineBody,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }

  /// F5.1 — the outbox header shown over messages waiting on your phone.
  Widget _waitingHeader() {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: NimnaSpacing.base * 2),
      child: Center(
        child: Text(
          l10n.chat_waitingHeader,
          style: NimnaText.caption.copyWith(color: tokens.textTertiary),
        ),
      ),
    );
  }

  Widget _seenCaption() {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 2, bottom: 4),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Text(
          l10n.session_readReceiptSeen,
          style: NimnaText.caption.copyWith(color: tokens.textTertiary),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    NimnaTokens tokens,
    AppLocalizations l10n,
  ) {
    final live = widget.controller.lineState == SessionLineState.live;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NimnaSpacing.base * 2,
        vertical: NimnaSpacing.base * 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                // Name the icon-only affordance for screen readers (framework
                // localized back tooltip; same precedent as NimnaBackButton).
                label: MaterialLocalizations.of(context).backButtonTooltip,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Leaving the screen is not hanging up (wireframe F5.4).
                  onTap: () => Navigator.of(context).maybePop(),
                  child: SizedBox(
                    width: NimnaSpacing.touchTargetMin,
                    height: NimnaSpacing.touchTargetMin,
                    child: Center(child: BackGlyph(color: tokens.textPrimary)),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  widget.label,
                  style: NimnaText.title2.copyWith(color: tokens.textPrimary),
                ),
              ),
              if (live)
                Semantics(
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => unawaited(widget.controller.hangup()),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: NimnaSpacing.base * 2,
                        vertical: NimnaSpacing.base * 2,
                      ),
                      child: Text(
                        l10n.chat_hangUp,
                        style: NimnaText.label.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                  ),
                )
              // F5.1/F5.13 — the Knock affordance (wireframe F5 chathead). Only
              // when not live and a coordinator wired it; "Knock again" after a
              // lapse. A deliberate human tap — the app never knocks for you.
              else if (widget.onKnock != null && widget.knockDeadline == null)
                Semantics(
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onKnock,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: NimnaSpacing.base * 2,
                        vertical: NimnaSpacing.base * 2,
                      ),
                      child: Text(
                        widget.knockLapsed
                            ? l10n.knock_again
                            : l10n.knock_knock,
                        style: NimnaText.label.copyWith(color: tokens.lineLive),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: NimnaSpacing.base),
          _statusLine(tokens, l10n),
        ],
      ),
    );
  }

  Widget _statusLine(NimnaTokens tokens, AppLocalizations l10n) {
    final state = widget.controller.lineState;
    final String label;
    final Color color;
    // F5.15 — a live-drop recovery (reconnect_coordinator phase) overrides the
    // controller's line state with the honest reconnect caption. No controller
    // ever sets SessionLineState.reconnecting; the PHASE is the source of truth.
    final phase = widget.reconnectPhase;
    if (phase != null && phase != ReconnectPhase.idle) {
      switch (phase) {
        case ReconnectPhase.reconnecting:
          label = l10n.session_lineDropped;
          color = tokens.lineIdle;
        case ReconnectPhase.recovered:
          label = l10n.session_lineRecovered;
          color = tokens.lineLive;
        case ReconnectPhase.lost:
          label = l10n.session_lineLost;
          color = tokens.lineIdle;
        case ReconnectPhase.idle:
          label = l10n.session_lineOnline;
          color = tokens.lineLive;
      }
      return _statusRow(tokens, label, color);
    }
    switch (state) {
      case SessionLineState.live:
        label = l10n.session_lineOnline;
        color = tokens.lineLive;
      case SessionLineState.connectionLost:
        // Terminal loss with no reconnect in flight (reconnect is S12). Render
        // the truthful subset of voice string 10, not the "…Trying to
        // reconnect…" promise — session_lineDropped is wired at S12. (PM ruling)
        label = l10n.session_lineLost;
        color = tokens.lineIdle;
      case SessionLineState.endedByYou:
        label = l10n.session_youHungUp;
        color = tokens.lineIdle;
      case SessionLineState.endedByPeer:
        label = l10n.session_peerHungUp;
        color = tokens.lineIdle;
      case SessionLineState.waiting:
        // S12 FOLD HOTSPOT (added here only to keep the exhaustive switch
        // compiling; final F5/knock-screen presentation is the chat lane's).
        // Knocked — waiting on a pick-up (string 6); the breathing live line.
        label = l10n.knock_waitingTitle;
        color = tokens.lineLive;
      case SessionLineState.reconnecting:
        // S12 FOLD HOTSPOT — a LIVE-session drop is auto-recovering (string 10,
        // the "…Trying to reconnect…" variant, distinct from the terminal
        // session_lineLost).
        label = l10n.session_lineDropped;
        color = tokens.lineIdle;
      case SessionLineState.offline:
      case SessionLineState.connecting:
        label = l10n.session_lineOffline;
        color = tokens.lineIdle;
    }
    return _statusRow(tokens, label, color);
  }

  Widget _statusRow(NimnaTokens tokens, String label, Color color) {
    return Row(
      children: [
        Container(width: 24, height: NimnaLine.thickness, color: color),
        const SizedBox(width: NimnaSpacing.base * 2),
        Text(
          label,
          style: NimnaText.caption.copyWith(color: tokens.textSecondary),
        ),
      ],
    );
  }

  /// The presence banner between the header and the thread (S16). It renders the
  /// two distinct "not on the line" surfaces the design keeps apart:
  ///  - screen 11 (knock in flight): knock_waitingCaption + a live countdown.
  ///  - F5.13 (lapsed): "No answer." (+ the §6.1 stale hint when repeated).
  /// Empty (a zero-height box) in the steady live/idle chat.
  Widget _presenceBanner(NimnaTokens tokens, AppLocalizations l10n) {
    final deadline = widget.knockDeadline;
    final List<Widget> lines;
    if (deadline != null) {
      final remaining = deadline.difference(DateTime.now()).inSeconds;
      lines = [
        Text(
          l10n.knock_waitingCaption,
          style: NimnaText.caption.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: NimnaSpacing.base),
        Text(
          l10n.knock_lapsesInSeconds(remaining < 0 ? 0 : remaining),
          style: NimnaText.caption.copyWith(color: tokens.textTertiary),
        ),
      ];
    } else if (widget.knockLapsed) {
      lines = [
        Text(
          l10n.knock_noAnswer,
          style: NimnaText.caption.copyWith(color: tokens.textSecondary),
        ),
        if (widget.knockStaleHint) ...[
          const SizedBox(height: NimnaSpacing.base),
          Text(
            l10n.knock_staleHint,
            style: NimnaText.caption.copyWith(color: tokens.textTertiary),
          ),
        ],
      ];
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NimnaSpacing.screenMargin,
        0,
        NimnaSpacing.screenMargin,
        NimnaSpacing.base * 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
    );
  }

  GlobalKey _keyFor(Uint8List recordId) =>
      _itemKeys.putIfAbsent(_hex(recordId), GlobalKey.new);

  static String _hex(Uint8List bytes) {
    const digits = '0123456789abcdef';
    final out = StringBuffer();
    for (final b in bytes) {
      out
        ..write(digits[(b >> 4) & 0x0F])
        ..write(digits[b & 0x0F]);
    }
    return out.toString();
  }
}
