import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'app_scope.dart';
import 'lock_gate.dart';
import 'routes.dart';
import 'theme.dart';

/// The Nimna app root: theme wiring (dark-first, system-following), l10n
/// (EN/DE/FR/ES/IT from the first widget), the LockGate perimeter above the
/// Navigator, and the named-route table.
///
/// S15: stateful so it can wire the push lane's app-root seams —
///  - notification tap → open → bring the Navigator to the root (the channel
///    list, where an incoming knock surfaces once F6 mounts, S16). The OS
///    already foregrounds the app; this lands it on the reconnect surface.
///  - foreground state → [PushService.setForeground] so a knock landing while
///    foregrounded shows no OS banner (in-app suppression, §3.2.1).
/// Both are no-ops with the inert push source (host tests, off-mobile).
class NimnaApp extends StatefulWidget {
  const NimnaApp({required this.services, this.locale, super.key});

  final NimnaServices services;

  /// Test override only; production follows the system locale (null).
  final Locale? locale;

  @override
  State<NimnaApp> createState() => _NimnaAppState();
}

class _NimnaAppState extends State<NimnaApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  StreamSubscription<void>? _tapSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tapSub = widget.services.pushService.notificationTaps.listen((_) {
      // Tap → open: land on the root route. The knock-answer surface (F6)
      // mounts there in S16; today this simply foregrounds onto the list.
      _navKey.currentState?.popUntil((route) => route.isFirst);
    });
    // Establish the initial foreground state (resumed at launch).
    widget.services.pushService.setForeground(foreground: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.services.pushService.setForeground(
      foreground: state == AppLifecycleState.resumed,
    );
  }

  @override
  void dispose() {
    unawaited(_tapSub?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: widget.services,
      child: MaterialApp(
        navigatorKey: _navKey,
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        locale: widget.locale,
        theme: nimnaTheme(Brightness.light),
        darkTheme: nimnaTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        onGenerateRoute: onGenerateRoute,
        // F1 first-run gate (S16): a fresh install lands on onboarding; every
        // later launch (the marker is set) goes straight to the channel list.
        // Read synchronously at build — a plaintext marker outside the lock
        // perimeter, so it is available before any unlock.
        initialRoute: widget.services.firstRun.hasSeenOnboarding()
            ? Routes.channelList
            : Routes.onboarding,
        // LockGate wraps the Navigator itself: sealed ⇒ the whole subtree
        // is replaced (zero-leak rule), never a route stacked above.
        builder: (context, navigator) => LockGate(
          keyService: widget.services.keyService,
          lockController: widget.services.lockController,
          child: navigator ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
