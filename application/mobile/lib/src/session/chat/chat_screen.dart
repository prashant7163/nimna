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
    super.key,
  });

  final SessionController controller;
  final String label;

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

  @override
  void initState() {
    super.initState();
    _sub = widget.controller.events.listen(_onEvent);
    // Screenshot detection is on ONLY while this screen is mounted — spec
    // §5.2's "detection fires only while content is on screen inside the app".
    _detector = widget.screenshotDetector ?? PlatformScreenshotDetector();
    _analyzer = widget.sensitiveAnalyzer ?? PlatformSensitiveContentAnalyzer();
    _screenshotSub = _detector.onScreenshot.listen((_) {
      // The controller additionally gates on liveness and seals CONTROL 0x03.
      widget.controller.noticeLocalScreenshot();
    });
    unawaited(_detector.start());
    // Kick the live path (register CRID / knock / accept). A no-op if already
    // established. TODO(S12): the entry point owns start() once presence lands.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.controller.lineState == SessionLineState.offline) {
        unawaited(widget.controller.start());
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
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
  List<Widget> _threadChildren() {
    final messages = widget.controller.messages;
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
