import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
  ];

  /// App title / wordmark. Always lowercase per the locked brand; identical in every locale.
  ///
  /// In en, this message translates to:
  /// **'nimna'**
  String get appTitle;

  /// Voice guide string 4, line 1 — empty channel list headline. Canonical copy, verbatim.
  ///
  /// In en, this message translates to:
  /// **'No lines yet.'**
  String get channelListEmptyHeadline;

  /// Voice guide string 4, line 2 — empty channel list body. Canonical copy, verbatim. 'Nimna code' is the code's only UI name (spec §2).
  ///
  /// In en, this message translates to:
  /// **'Create a Nimna code, or enter one you\'ve been given.'**
  String get channelListEmptyBody;

  /// Primary action on the empty channel list (voice guide register notes: buttons are verbs, one or two words). Gated by subscription from S12; stub in S7.
  ///
  /// In en, this message translates to:
  /// **'Create a code'**
  String get actionCreateCode;

  /// Secondary action on the empty channel list — join with a code you've been given. Never paywalled. Stub in S7.
  ///
  /// In en, this message translates to:
  /// **'Enter a code'**
  String get actionEnterCode;

  /// Message-actions card: starts a reply to the long-pressed message (voice string 21 family; components.md message actions). DS fold, consumed from S10.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get chat_messageActionReply;

  /// Message-actions card: a11y/name for the emoji quick row (voice string 21). The visible affordance is the emoji row itself. DS fold, consumed from S10.
  ///
  /// In en, this message translates to:
  /// **'React'**
  String get chat_messageActionReact;

  /// Message-actions card: the local per-message delete (spec section 6). Rides the same card as react/reply; previously long-press to delete on waiting bubbles. DS fold, consumed from S10.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get chat_messageActionDelete;

  /// Reply compose strip overline (voice string 20). Rendered as the micro uppercase style; casing is a text-style concern, not a copy concern. DS fold, consumed from S10.
  ///
  /// In en, this message translates to:
  /// **'Replying to'**
  String get chat_replyingToLabel;

  /// A11y label for the X that abandons the reply compose strip (voice string 20). Composer text survives cancellation. DS fold, consumed from S10.
  ///
  /// In en, this message translates to:
  /// **'Cancel reply'**
  String get chat_replyCancelA11y;

  /// CANONICAL, spec v0.2.1 section 5.8 verbatim. Quote-block tombstone when the referenced message is unknown, deleted, or expired - one identical string for all three causes; it never says why. Never edit outside a spec change. DS fold, consumed from S10.
  ///
  /// In en, this message translates to:
  /// **'Message no longer available.'**
  String get chat_replyTombstone;

  /// Quoted-media preview label beside the 32 px thumbnail when the referenced message is an image (voice string 20). DS fold, consumed from S10.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get chat_replyPreviewPhoto;

  /// Quoted-media preview label beside the thumbnail when the referenced message is a document (voice string 20). DS fold, consumed from S10.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get chat_replyPreviewDocument;

  /// A11y label for your own reaction chip (voice string 21). Tap removes unconditionally (spec section 5.8). S10 MUST bound the substitution per designs/handoff/arb-stubs-reply-reactions.md: 64-byte wire bound + C0/C1 and bidi/format-control strip — the visual chip clamp does not cover this string. DS fold, consumed from S10.
  ///
  /// In en, this message translates to:
  /// **'You reacted {emoji}. Tap to remove.'**
  String chat_reactionOwnA11y(String emoji);

  /// A11y label for the peer's reaction chip (voice string 21). 'They' is deliberate - the peer has no name; the channel label is local-only. Same S10 substitution bound as chat_reactionOwnA11y. DS fold, consumed from S10.
  ///
  /// In en, this message translates to:
  /// **'They reacted {emoji}.'**
  String chat_reactionPeerA11y(String emoji);

  /// A11y label for the plus disc at the end of the emoji quick row - opens the system emoji keyboard; first emoji grapheme is taken (compose rule, spec section 5.5). DS fold, consumed from S10.
  ///
  /// In en, this message translates to:
  /// **'Choose another emoji'**
  String get chat_reactionPickMoreA11y;

  /// CANONICAL, spec v0.2.1 section 3.1 verbatim (voice string 19). Self-join guard on the code-entry surface: detected locally, nothing is sent, warning-toned, no shake. Never edit outside a spec change. DS fold, consumed from S9.
  ///
  /// In en, this message translates to:
  /// **'This is your own Nimna code — share it with the other person.'**
  String get pairing_selfJoinOwnCode;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'es', 'fr', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
