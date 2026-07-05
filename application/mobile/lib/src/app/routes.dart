import 'package:flutter/widgets.dart';

import '../ui/screens/channel_list_screen.dart';
import 'transitions.dart';

/// Named routes (Navigator 1.0, app-architecture.md §8.3). v1 has no
/// URL/deep-link surface; push-tap is an app-launch event (S15), not a
/// route URL.
abstract final class Routes {
  static const String channelList = '/';
}

Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  switch (settings.name) {
    case Routes.channelList:
      return NimnaPageRoute(
        settings: settings,
        builder: (context) => const ChannelListScreen(),
      );
  }
  return null;
}
