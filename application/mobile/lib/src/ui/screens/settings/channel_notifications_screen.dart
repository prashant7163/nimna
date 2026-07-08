import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/app_scope.dart';
import '../../../domain/channel_repository.dart';
import '../../../presence/push_opt_in.dart';
import '../../../presence/push_opt_in_tile.dart';
import '../../theme/nimna_tokens.dart';
import '../../widgets/nav_bar.dart';
import '../../widgets/nimna_toggle.dart';

/// F7 — the per-line channel settings (wireframe F7.1, spec §6). Everything
/// here is per-channel and stored ONLY on this phone. Three toggles, each with
/// string-verbatim honesty in place (the caption IS the disclosure, never a
/// one-time dialog):
///
///  - **Notify me when they knock** (push) — opt-IN, DEFAULT OFF (string 18).
///  - **Read receipts** — opt-IN, DEFAULT OFF (USER 2026-07-07): when on, the
///    peer sees "Seen" under messages you read. Rides CONTROL 0x02.
///  - **Typing indicator** — DEFAULT ON (USER 2026-07-07); this is the OFF
///    switch (the F7 mitigation for the keystroke-timing leak). Rides
///    CONTROL 0x01.
///
/// Receipts/typing are honored by the peer's app, not enforced (same honor
/// system as disappearing messages). A change persists into the channel record
/// ciphertext and takes effect from the NEXT session start (the live session's
/// preferences are captured at launch). Every string is ARB-sourced; the label
/// is local user data; layout survives German-length copy.
class ChannelNotificationsScreen extends StatefulWidget {
  const ChannelNotificationsScreen({
    required this.channelId,
    required this.label,
    super.key,
  });

  final Uint8List channelId;

  /// The channel's local label (F7 header). Local-only (spec §6).
  final String label;

  @override
  State<ChannelNotificationsScreen> createState() =>
      _ChannelNotificationsScreenState();
}

class _ChannelNotificationsScreenState
    extends State<ChannelNotificationsScreen> {
  bool _push = false;
  bool _readReceipts = false;
  bool _typing = true;
  bool _read = false;

  ChannelRepository get _channels => AppScope.of(context).storage.channels;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_read) {
      return;
    }
    _read = true;
    // Read against the currently-open channel repo (the perimeter is open while
    // this screen shows) — never a captured, stale repo.
    final record = _channels.byId(widget.channelId);
    _push = PushOptIn(_channels).isEnabled(widget.channelId);
    _readReceipts = record?.readReceiptsOptIn ?? false;
    _typing = record?.typingEnabled ?? true;
  }

  Future<void> _onPushChanged(bool value) async {
    final services = AppScope.of(context);
    setState(() => _push = value);
    await PushOptIn(
      services.storage.channels,
    ).setEnabled(widget.channelId, enabled: value);
    // Fire-and-forget: token acquisition / announce-or-revoke. A failure only
    // means the peer can't wake this phone — never a data leak.
    unawaited(
      services.pushService.onOptInChanged(widget.channelId, enabled: value),
    );
  }

  Future<void> _onReadReceiptsChanged(bool value) async {
    setState(() => _readReceipts = value);
    final record = _channels.byId(widget.channelId);
    if (record != null && record.readReceiptsOptIn != value) {
      await _channels.update(record.copyWith(readReceiptsOptIn: value));
    }
  }

  Future<void> _onTypingChanged(bool value) async {
    setState(() => _typing = value);
    final record = _channels.byId(widget.channelId);
    if (record != null && record.typingEnabled != value) {
      await _channels.update(record.copyWith(typingEnabled: value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NimnaNavBar(title: widget.label),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NimnaSpacing.screenMargin,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.channelSettings_subtitle,
                    style: text.bodySmall?.copyWith(color: tokens.textTertiary),
                  ),
                  const SizedBox(height: NimnaSpacing.base * 2),
                  PushOptInTile(enabled: _push, onChanged: _onPushChanged),
                  _ToggleRow(
                    label: l10n.settings_readReceiptsLabel,
                    caption: l10n.settings_readReceiptsCaption,
                    value: _readReceipts,
                    onChanged: (v) => unawaited(_onReadReceiptsChanged(v)),
                  ),
                  _ToggleRow(
                    label: l10n.settings_typingLabel,
                    caption: l10n.settings_typingCaption,
                    value: _typing,
                    onChanged: (v) => unawaited(_onTypingChanged(v)),
                    hairline: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One per-line toggle row (F7 `.setrow` + toggle): label + always-visible
/// honesty caption + [NimnaToggle]. Mirrors [PushOptInTile]'s shape so the
/// three rows read as one list. Caption wraps — survives German-length copy.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.caption,
    required this.value,
    required this.onChanged,
    this.hairline = true,
  });

  final String label;
  final String caption;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool hairline;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      toggled: value,
      label: label,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: NimnaSpacing.listRowSettings,
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: hairline
              ? Border(bottom: BorderSide(color: tokens.hairline))
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: text.labelLarge?.copyWith(color: tokens.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    style: text.bodySmall?.copyWith(color: tokens.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            NimnaToggle(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
