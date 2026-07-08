import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../theme/nimna_tokens.dart';
import '../../widgets/nimna_symbol.dart';

/// F1 — first-run onboarding (USER 2026-07-08: FOUR screens, never more; shown
/// exactly once per install). Pure reading — no network is touched, no
/// permission asked (spec §5.2's informed-consent flow precedes any ask).
///
///  - F1.1 what it is (voice string 1)
///  - F1.2 how pairing works (voice string 2)
///  - F1.3 what we cannot see (voice string 3) + the honest relay-metadata note
///  - F1.4 the screenshot terms (voice string 11, informed consent) — plus the
///    Android ≤13 caveat, rendered CONDITIONALLY (USER 2026-07-08): iPhone and
///    Android 14+ see the clean "always tells them" copy; only Android 13 and
///    older see the honest sub-14 caveat.
///
/// No in-app back control (platform swipe-back rides the PageView). Skip on the
/// first three exits to the empty list (F4.4); the consent screen (F1.4) has no
/// Skip — Start is its single action. There is no resumable state: relaunching
/// mid-onboarding restarts at F1.1 (the "seen" marker is written only on exit).
/// Every string is ARB-sourced; layout survives German-length copy; no
/// hardcoded left/right.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({this.androidCaveatProbe, super.key});

  /// Resolves whether the F1.4 Android screenshot caveat applies (Android 13
  /// and older). Injected in tests; production probes the native SDK level via
  /// the screenshot method channel. iOS and Android 14+ resolve to false.
  final Future<bool> Function()? androidCaveatProbe;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pages = PageController();
  int _index = 0;
  bool _androidCaveat = false;

  static const int _pageCount = 4;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveCaveat());
  }

  Future<void> _resolveCaveat() async {
    final probe = widget.androidCaveatProbe ?? _defaultAndroidCaveatProbe;
    final show = await probe();
    if (mounted && show != _androidCaveat) {
      setState(() => _androidCaveat = show);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _onPage(int index) => setState(() => _index = index);

  void _next() {
    _pages.nextPage(
      duration: NimnaMotion.standard,
      curve: NimnaMotion.easeStandard,
    );
  }

  Future<void> _finish() async {
    final services = AppScope.of(context);
    final navigator = Navigator.of(context);
    await services.firstRun.markSeen();
    if (!mounted) {
      return;
    }
    // Skip → F4.4 empty list; Start → F4.4 empty list. Replace so onboarding is
    // never on the back stack (it exists exactly once per install).
    navigator.pushReplacementNamed(Routes.channelList);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final last = _index == _pageCount - 1;
    return Scaffold(
      backgroundColor: tokens.surface0,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: _onPage,
                children: [
                  _OnboardingPage(
                    headline: l10n.onboarding_whatItIsHeadline,
                    body: l10n.onboarding_whatItIsBody,
                    symbol: true,
                  ),
                  _OnboardingPage(
                    headline: l10n.onboarding_pairingHeadline,
                    body: l10n.onboarding_pairingBody,
                  ),
                  _OnboardingPage(
                    headline: l10n.onboarding_cannotSeeHeadline,
                    body: l10n.onboarding_cannotSeeBody,
                    note: l10n.onboarding_cannotSeeRelayNote,
                  ),
                  _OnboardingPage(
                    headline: l10n.screenshot_onboardingDisclosure,
                    // The disclosure IS the copy for F1.4 (voice string 11); the
                    // conditional caveat is the only body it carries, and only
                    // on Android 13 and older.
                    body: _androidCaveat
                        ? l10n.screenshot_onboardingAndroidCaveat
                        : null,
                  ),
                ],
              ),
            ),
            _pips(tokens),
            const SizedBox(height: NimnaSpacing.base * 5),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NimnaSpacing.screenMargin,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: last ? () => unawaited(_finish()) : _next,
                    child: Text(
                      last ? l10n.onboarding_start : l10n.onboarding_next,
                    ),
                  ),
                  // No Skip on the consent screen (F1.4) — Start is its single
                  // action (wireframe F1.4).
                  SizedBox(
                    height: NimnaSpacing.touchTargetMin,
                    child: last
                        ? null
                        : Center(
                            child: TextButton(
                              onPressed: () => unawaited(_finish()),
                              child: Text(l10n.onboarding_skip),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: NimnaSpacing.base * 4),
          ],
        ),
      ),
    );
  }

  Widget _pips(NimnaTokens tokens) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < _pageCount; i++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == _index ? tokens.textPrimary : tokens.textDisabled,
            ),
          ),
        ),
    ],
  );
}

/// One onboarding reading beat: headline in the top third (never vertically
/// centered — foundations: calm ≠ empty), body, and an optional honest note.
class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.headline,
    this.body,
    this.note,
    this.symbol = false,
  });

  final String headline;
  final String? body;
  final String? note;
  final bool symbol;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: NimnaSpacing.screenMargin,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: NimnaSpacing.base * 16),
          if (symbol) ...[
            Center(child: NimnaSymbol(tokens: tokens)),
            const SizedBox(height: NimnaSpacing.base * 8),
          ],
          Text(headline, style: text.titleLarge),
          if (body != null) ...[
            const SizedBox(height: NimnaSpacing.base * 4),
            Text(
              body!,
              style: text.bodyLarge?.copyWith(color: tokens.textSecondary),
            ),
          ],
          if (note != null) ...[
            const SizedBox(height: NimnaSpacing.base * 4),
            Text(
              note!,
              style: text.bodySmall?.copyWith(color: tokens.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Production caveat probe: the F1.4 Android caveat applies only on Android 13
/// and older (SDK_INT < 34), where screenshot detection is unavailable (the
/// honest sub-14 gap, USER 2026-07-07/08). iOS and Android 14+ return false —
/// they see the clean "it will always tell the other person" copy. Reuses the
/// existing screenshot method channel (no new channel); a missing handler or
/// any failure fails toward the clean copy (never a manufactured worry).
Future<bool> _defaultAndroidCaveatProbe() async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return false;
  }
  try {
    const channel = MethodChannel('app.nimna/screenshot');
    final sdk = await channel.invokeMethod<int>('getSdkInt');
    return sdk != null && sdk < 34;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
