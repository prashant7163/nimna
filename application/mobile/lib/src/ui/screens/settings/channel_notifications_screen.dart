import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/app_scope.dart';
import '../../../presence/push_opt_in.dart';
import '../../../presence/push_opt_in_tile.dart';
import '../../theme/nimna_tokens.dart';
import '../../widgets/nav_bar.dart';

/// A MINIMAL, F7-consistent per-line settings surface (S15) — the reachable
/// mount that makes the `PushOptInTile` live end-to-end (requirement 4). The
/// FULL F7 (label edit · read receipts · typing · per-line wipe) is S16; this
/// surface ships only the push toggle so push is actually usable/testable now.
///
/// The toggle writes through [PushOptIn.setEnabled] (persisted inside the
/// channel-record ciphertext) and notifies [PushService.onOptInChanged], which
/// acquires THIS device's own token on opt-in (the honest moment for the OS
/// permission prompt) and announces / revokes it on any live session. Push is
/// per-line, opt-IN, DEFAULT OFF; off is pure burner-line mode.
///
/// Every string is ARB-sourced; the channel [label] is local user data.
class ChannelNotificationsScreen extends StatefulWidget {
  const ChannelNotificationsScreen({
    required this.channelId,
    required this.label,
    super.key,
  });

  final Uint8List channelId;

  /// The channel's local label (F7 header "‹ {label}"). Local-only (spec §6).
  final String label;

  @override
  State<ChannelNotificationsScreen> createState() =>
      _ChannelNotificationsScreenState();
}

class _ChannelNotificationsScreenState
    extends State<ChannelNotificationsScreen> {
  bool _enabled = false;
  bool _read = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_read) {
      return;
    }
    _read = true;
    // A fresh PushOptIn over the currently-open channel repo (the perimeter is
    // open while this screen shows) — never a captured, stale repo. Read here
    // (not initState) so the AppScope inherited-widget lookup is legal.
    _enabled = PushOptIn(
      AppScope.of(context).storage.channels,
    ).isEnabled(widget.channelId);
  }

  Future<void> _onChanged(bool value) async {
    final services = AppScope.of(context);
    setState(() => _enabled = value);
    await PushOptIn(
      services.storage.channels,
    ).setEnabled(widget.channelId, enabled: value);
    // Fire-and-forget: token acquisition / announce-or-revoke. A failure only
    // means the peer can't wake this phone — never a data leak.
    unawaited(
      services.pushService.onOptInChanged(widget.channelId, enabled: value),
    );
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
                  PushOptInTile(enabled: _enabled, onChanged: _onChanged),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
