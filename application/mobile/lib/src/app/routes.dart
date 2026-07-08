import 'package:flutter/widgets.dart';

import '../session/chat/chat_screen.dart';
import '../session/chat/line_presence.dart';
import '../ui/screens/channel_list_screen.dart';
import '../ui/screens/knock_received_screen.dart';
import '../ui/screens/onboarding/onboarding_screen.dart';
import '../ui/screens/paywall/paywall_screen.dart';
import '../ui/screens/settings/app_lock_setup_screen.dart';
import '../ui/screens/settings/channel_notifications_screen.dart';
import '../ui/screens/settings/diagnostics_screen.dart';
import '../ui/screens/settings/notifications_directory_screen.dart';
import '../ui/screens/settings/settings_root_screen.dart';
import 'app_scope.dart';
import 'transitions.dart';

/// Named routes (Navigator 1.0, app-architecture.md §8.3). v1 has no
/// URL/deep-link surface; push-tap is an app-launch event (S15), not a
/// route URL.
abstract final class Routes {
  static const String channelList = '/';

  /// F1 — first-run onboarding (S16). Launch route only when onboarding has
  /// not been seen (the first-run gate lives in the app root); it replaces
  /// itself with [channelList] on Skip/Start and is never on the back stack.
  static const String onboarding = '/onboarding';

  /// F8.1 — app settings (S13).
  static const String settings = '/settings';

  /// F8.2 — app-lock setup / manage (S13).
  static const String appLock = '/settings/app-lock';

  /// F8 — diagnostics export (S16). A deliberate, in-memory share of the
  /// structurally content-free local log; nothing auto-uploads. Inside the
  /// app-lock perimeter.
  static const String diagnostics = '/settings/diagnostics';

  /// F8 → per-line notifications directory (S15). Lists lines; each opens
  /// [channelNotifications]. The full F7 per-line screen is S16.
  static const String notifications = '/settings/notifications';

  /// F7 (minimal) — per-line push settings (S15). Pushed with a
  /// [ChannelNotificationsArgs] (channelId + local label).
  static const String channelNotifications = '/settings/notifications/channel';

  /// F9 — subscription paywall / creation gate (S17). Pushed only from
  /// `startCreateLine` when the store has no active creation subscription;
  /// pops a [PaywallResult]. Never a launch route, never joined-from.
  static const String paywall = '/paywall';

  /// F6 — the incoming-knock surface (S16). Pushed with a [KnockScreenArgs]
  /// (the engaged session + the channel's local label) — the target the
  /// push-tap → open path lands on when the app opens into a live knock. Pick
  /// up → the chat (F5); Ignore → silence. Never a launch route.
  static const String knock = '/knock';

  /// F5 — the live chat session (S10). Pushed with a [ChatScreenArgs] carrying
  /// a built [SessionController] + the channel's local label. The standalone
  /// entry point; the presence-mounted line goes through [line].
  static const String chat = '/chat';

  /// F4 → F5 — the opened line (S16). Pushed with a [LinePresenceArgs]
  /// (channelId + local label) from an F4 row tap. [LinePresence] owns the
  /// per-open-line choreography: connect LISTENING (receivable), offer Knock,
  /// surface an incoming knock (F6), and bridge to the live chat. Never a
  /// launch route.
  static const String line = '/line';
}

Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  switch (settings.name) {
    case Routes.channelList:
      return NimnaPageRoute(
        settings: settings,
        builder: (context) => const ChannelListScreen(),
      );
    case Routes.onboarding:
      return NimnaPageRoute(
        settings: settings,
        builder: (context) => const OnboardingScreen(),
      );
    case Routes.settings:
      return NimnaPageRoute(
        settings: settings,
        builder: (context) => const SettingsRootScreen(),
      );
    case Routes.appLock:
      return NimnaPageRoute(
        settings: settings,
        builder: (context) => const AppLockSetupScreen(),
      );
    case Routes.diagnostics:
      return NimnaPageRoute(
        settings: settings,
        builder: (context) => const DiagnosticsScreen(),
      );
    case Routes.notifications:
      return NimnaPageRoute(
        settings: settings,
        builder: (context) => const NotificationsDirectoryScreen(),
      );
    case Routes.channelNotifications:
      final args = settings.arguments as ChannelNotificationsArgs;
      return NimnaPageRoute(
        settings: settings,
        builder: (context) => ChannelNotificationsScreen(
          channelId: args.channelId,
          label: args.label,
        ),
      );
    case Routes.knock:
      final args = settings.arguments as KnockScreenArgs;
      return NimnaPageRoute(
        settings: settings,
        builder: (context) =>
            KnockReceivedScreen(session: args.session, label: args.label),
      );
    case Routes.paywall:
      return NimnaPageRoute<PaywallResult>(
        settings: settings,
        builder: (context) => const PaywallScreen(),
      );
    case Routes.chat:
      final args = settings.arguments as ChatScreenArgs;
      return NimnaPageRoute(
        settings: settings,
        builder: (context) =>
            ChatScreen(controller: args.controller, label: args.label),
      );
    case Routes.line:
      final args = settings.arguments as LinePresenceArgs;
      return NimnaPageRoute(
        settings: settings,
        builder: (context) {
          // A fresh launcher bound to the currently-open repositories (the
          // factory the S15 forward-requirement wired push into).
          final services = AppScope.of(context);
          return LinePresence(
            launcher: services.sessionLauncher(),
            diag: services.diag,
            channelId: args.channelId,
            label: args.label,
          );
        },
      );
  }
  return null;
}
