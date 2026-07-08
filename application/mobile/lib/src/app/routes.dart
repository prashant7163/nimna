import 'package:flutter/widgets.dart';

import '../session/chat/chat_screen.dart';
import '../ui/screens/channel_list_screen.dart';
import '../ui/screens/paywall/paywall_screen.dart';
import '../ui/screens/settings/app_lock_setup_screen.dart';
import '../ui/screens/settings/channel_notifications_screen.dart';
import '../ui/screens/settings/notifications_directory_screen.dart';
import '../ui/screens/settings/settings_root_screen.dart';
import 'transitions.dart';

/// Named routes (Navigator 1.0, app-architecture.md §8.3). v1 has no
/// URL/deep-link surface; push-tap is an app-launch event (S15), not a
/// route URL.
abstract final class Routes {
  static const String channelList = '/';

  /// F8.1 — app settings (S13).
  static const String settings = '/settings';

  /// F8.2 — app-lock setup / manage (S13).
  static const String appLock = '/settings/app-lock';

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

  /// F5 — the live chat session (S10). Pushed with a [ChatScreenArgs] carrying
  /// a built [SessionController] + the channel's local label. The entry points
  /// that construct the controller (channel-row tap → knock, incoming-knock
  /// pick-up → accept) are S12; never a launch route.
  static const String chat = '/chat';
}

Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  switch (settings.name) {
    case Routes.channelList:
      return NimnaPageRoute(
        settings: settings,
        builder: (context) => const ChannelListScreen(),
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
  }
  return null;
}
