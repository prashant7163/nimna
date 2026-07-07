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
  const ChatScreen({required this.controller, required this.label, super.key});

  final SessionController controller;
  final String label;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  StreamSubscription<ChatEvent>? _sub;
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};
  MessageView? _replyingTo;

  @override
  void initState() {
    super.initState();
    _sub = widget.controller.events.listen(_onEvent);
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
    _scroll.dispose();
    super.dispose();
  }

  void _onEvent(ChatEvent event) {
    if (!mounted) {
      return;
    }
    setState(() {});
    if (event is MessageArrived) {
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
    final messages = widget.controller.messages;
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
                children: [
                  for (final m in messages)
                    KeyedSubtree(
                      key: _keyFor(m.recordId),
                      child: MessageBubble(
                        message: m,
                        onLongPress: () => unawaited(_openActions(m)),
                        onTapQuote: m.reply?.referentRecordId == null
                            ? null
                            : () =>
                                  _scrollToReferent(m.reply!.referentRecordId!),
                      ),
                    ),
                  if (widget.controller.peerTyping) const PeerTypingBubble(),
                ],
              ),
            ),
            Composer(
              onSend: _send,
              onTyping: widget.controller.setTyping,
              replyingTo: _replyingTo,
              onCancelReply: () => setState(() => _replyingTo = null),
            ),
          ],
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
        label = l10n.session_lineDropped;
        color = tokens.lineIdle;
      case SessionLineState.endedByYou:
        label = l10n.session_youHungUp;
        color = tokens.lineIdle;
      case SessionLineState.endedByPeer:
        label = l10n.session_peerHungUp;
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
