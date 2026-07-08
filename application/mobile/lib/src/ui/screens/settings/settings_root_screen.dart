import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../theme/nimna_tokens.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/nav_bar.dart';
import '../../widgets/wipe_sheet.dart';

/// F8.1 — Settings root. Five rows; the destructive row sits apart at the
/// bottom, never adjacent to anything routine. No "account", no
/// "backup & sync", no "devices" rows — they cannot exist here, and their
/// absence is the product.
///
/// Notifications (per-line directory) and Relay (F8.4) rows are inert in
/// S13 — their target screens belong to later sessions. Licenses opens the
/// standard OSS list.
class SettingsRootScreen extends StatelessWidget {
  const SettingsRootScreen({super.key});

  Future<void> _wipeEverything(BuildContext context) async {
    final services = AppScope.of(context);
    final navigator = Navigator.of(context);
    final wiped = await showFullWipeSheet(
      context,
      onWipe: services.wipe.fullWipe,
    );
    if (wiped ?? false) {
      // F8.3 exit: back to the F4.4 empty list, indistinguishable from a
      // fresh install.
      navigator.popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final services = AppScope.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NimnaNavBar(title: l10n.settings_title),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: NimnaSpacing.screenMargin,
                ),
                children: [
                  ListenableBuilder(
                    listenable: services.lockController,
                    builder: (context, _) {
                      final lock = services.lockController;
                      return SettingsRow(
                        label: l10n.settings_rowAppLock,
                        caption: !lock.enabled
                            ? l10n.settings_rowAppLockOff
                            : lock.biometricEnabled
                            ? l10n.settings_rowAppLockOnBiometric
                            : l10n.settings_rowAppLockOn,
                        onTap: () =>
                            Navigator.of(context).pushNamed(Routes.appLock),
                      );
                    },
                  ),
                  SettingsRow(
                    label: l10n.settings_rowNotifications,
                    caption: l10n.settings_rowNotificationsCaption,
                    // Per-line push directory (S15): lists lines, each flips
                    // its own opt-in (default off). Full F7 polish is S16.
                    onTap: () =>
                        Navigator.of(context).pushNamed(Routes.notifications),
                  ),
                  SettingsRow(
                    label: l10n.settings_rowRelay,
                    caption: l10n.settings_rowRelayCaption,
                    // F8.4 ships with a later session; inert row in S13.
                    onTap: null,
                  ),
                  SettingsRow(
                    label: l10n.settings_rowLicenses,
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: l10n.appTitle,
                    ),
                  ),
                  SettingsRow(
                    label: l10n.settings_rowDiagnostics,
                    caption: l10n.settings_rowDiagnosticsCaption,
                    // A deliberate export of the content-free local log; nothing
                    // auto-uploads (architect Concern 2). Inside the perimeter.
                    onTap: () =>
                        Navigator.of(context).pushNamed(Routes.diagnostics),
                  ),
                  const SizedBox(height: 24),
                  SettingsRow(
                    label: l10n.settings_rowWipeEverything,
                    caption: l10n.settings_rowWipeEverythingCaption,
                    danger: true,
                    hairline: false,
                    onTap: () => _wipeEverything(context),
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

/// One settings row (wireframe `.setrow`): label + optional caption,
/// trailing chevron when tappable, 1 px hairline beneath unless the row
/// closes a group. Caption wraps — layouts survive German-length strings.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.label,
    this.caption,
    this.onTap,
    this.danger = false,
    this.hairline = true,
    super.key,
  });

  final String label;
  final String? caption;
  final VoidCallback? onTap;
  final bool danger;
  final bool hairline;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: text.labelLarge?.copyWith(
                        color: danger ? tokens.danger : tokens.textPrimary,
                      ),
                    ),
                    if (caption != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        caption!,
                        style: text.bodySmall?.copyWith(
                          color: tokens.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 12),
                ChevronGlyph(
                  color: danger ? tokens.danger : tokens.textTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
