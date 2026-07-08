/// Picks THIS platform's [PlatformPushSource]: native APNs on iOS, FCM on
/// Android, and [InertPushSource] everywhere else (host tests, desktop) so
/// the firebase SDK is never even constructed off Android. Kept tiny and
/// dependency-light so `flutter test` can bypass it entirely by injecting a
/// source directly into [PushService].
///
/// The `dart:io` `Platform` check is the ONLY platform-branch in the push
/// lane; both concrete sources are otherwise platform-agnostic Dart.
library;

import 'dart:io' show Platform;

import 'apns_push_source.dart';
import 'fcm_push_source.dart';
import 'platform_push_source.dart';

/// Constructs the push source for the running platform. iOS → native APNs
/// (no SDK); Android → FCM (the one Google SDK); otherwise inert.
PlatformPushSource defaultPushSource() {
  if (Platform.isIOS) {
    return ApnsPushSource();
  }
  if (Platform.isAndroid) {
    return FcmPushSource();
  }
  return const InertPushSource();
}
