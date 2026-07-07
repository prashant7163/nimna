/// The lifecycle → background-grace bridge (spec §3.3). Maps
/// [AppLifecycleState] transitions onto [BackgroundGrace]: backgrounding
/// starts the ~30 s grace (the live socket is briefly held so a quick
/// app-switch does not tear the line down); foregrounding cancels it; on
/// expiry the grace's own callback closes the session.
///
/// Thin and fence-pinned: this is the ONLY WidgetsBinding-coupled file in the
/// presence lane (the grace/reconnect/knock logic is pure Dart, unit-tested).
/// The real OS background-socket behavior is proven on-device (S18); here we
/// only wire the transitions.
library;

import 'package:flutter/widgets.dart';

import 'background_grace.dart';

class AppLifecycleGate with WidgetsBindingObserver {
  AppLifecycleGate({required this._grace, WidgetsBinding? binding})
    : _binding = binding ?? WidgetsBinding.instance;

  final BackgroundGrace _grace;
  final WidgetsBinding _binding;

  /// Begin observing lifecycle transitions.
  void attach() => _binding.addObserver(this);

  /// Stop observing and cancel any pending grace window.
  void detach() {
    _binding.removeObserver(this);
    _grace.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Backgrounded — start the grace window.
        _grace.onBackground();
      case AppLifecycleState.resumed:
        // Foregrounded within the window — cancel silently.
        _grace.onForeground();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // Transient (call sheet / control centre) or teardown — neither
        // starts nor cancels the grace.
        break;
    }
  }
}
