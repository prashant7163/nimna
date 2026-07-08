import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../theme/nimna_tokens.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/nav_bar.dart';

/// F8.1 → the per-line notifications directory (S15). The Settings
/// "Notifications" row opens this; it lists every line so each can flip its
/// own push toggle. Push is per-line, opt-IN, DEFAULT OFF, so this is a plain
/// navigation list — no on/off state is surfaced here (the caption IS the
/// disclosure, on the per-line screen). The full F7 arrives at S16; this is
/// the reachable mount that makes push usable now (requirement 4).
///
/// Reachable only when unlocked (the store is open); all copy is ARB-sourced,
/// each channel [label] is local user data.
class NotificationsDirectoryScreen extends StatelessWidget {
  const NotificationsDirectoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;
    final channels = AppScope.of(context).storage.channels;
    final lines = channels.isOpen ? channels.all : const [];

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NimnaNavBar(title: l10n.settings_rowNotifications),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NimnaSpacing.screenMargin,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  l10n.settings_rowNotificationsCaption,
                  style: text.bodySmall?.copyWith(color: tokens.textTertiary),
                ),
              ),
            ),
            const SizedBox(height: NimnaSpacing.base * 2),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: NimnaSpacing.screenMargin,
                ),
                children: [
                  for (final record in lines)
                    _LineRow(
                      label: record.label,
                      onTap: () => Navigator.of(context).pushNamed(
                        Routes.channelNotifications,
                        arguments: ChannelNotificationsArgs(
                          channelId: record.id,
                          label: record.label,
                        ),
                      ),
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

/// One line row: local label + chevron (mirror of `SettingsRow`, label-only).
class _LineRow extends StatelessWidget {
  const _LineRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: NimnaSpacing.listRowSettings,
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tokens.hairline)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: text.labelLarge?.copyWith(color: tokens.textPrimary),
                ),
              ),
              const SizedBox(width: 12),
              ChevronGlyph(color: tokens.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Route args for the per-line notifications screen.
class ChannelNotificationsArgs {
  const ChannelNotificationsArgs({
    required this.channelId,
    required this.label,
  });

  final Uint8List channelId;
  final String label;
}
