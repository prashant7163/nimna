// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'nimna';

  @override
  String get channelListEmptyHeadline => 'No lines yet.';

  @override
  String get channelListEmptyBody =>
      'Create a Nimna code, or enter one you\'ve been given.';

  @override
  String get actionCreateCode => 'Create a code';

  @override
  String get actionEnterCode => 'Enter a code';
}
