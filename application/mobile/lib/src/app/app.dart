import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'app_scope.dart';
import 'lock_gate.dart';
import 'routes.dart';
import 'theme.dart';

/// The Nimna app root: theme wiring (dark-first, system-following), l10n
/// (EN/DE/FR/ES/IT from the first widget), the LockGate perimeter above the
/// Navigator, and the named-route table.
class NimnaApp extends StatelessWidget {
  const NimnaApp({required this.services, this.locale, super.key});

  final NimnaServices services;

  /// Test override only; production follows the system locale (null).
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        locale: locale,
        theme: nimnaTheme(Brightness.light),
        darkTheme: nimnaTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        onGenerateRoute: onGenerateRoute,
        initialRoute: Routes.channelList,
        // LockGate wraps the Navigator itself: sealed ⇒ the whole subtree
        // is replaced (zero-leak rule), never a route stacked above.
        builder: (context, navigator) => LockGate(
          keyService: services.keyService,
          child: navigator ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
