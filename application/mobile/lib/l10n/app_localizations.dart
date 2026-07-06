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

  /// F8.1 header, and the F4 list-footer entry row that opens it. S13.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings_title;

  /// F8.1 row label. S13.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get settings_rowAppLock;

  /// F8.1 App-lock row caption while the lock is off, verbatim from the wireframe. S13.
  ///
  /// In en, this message translates to:
  /// **'Off — a PIN or your face, before anything shows'**
  String get settings_rowAppLockOff;

  /// App-lock row value when the lock is on without biometrics (hi-fi screen 08 renders the on-state as 'On'). S13.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get settings_rowAppLockOn;

  /// App-lock row caption when lock + biometric are on, verbatim from F8.2's exit note. NOTE: 'Face ID' is the iOS name; the Android biometric naming question is flagged in progress/SESSION-13.md for the design loop. S13.
  ///
  /// In en, this message translates to:
  /// **'On — PIN + Face ID'**
  String get settings_rowAppLockOnBiometric;

  /// F8.1 row label. The row is a per-line directory, not a master switch (spec section 3.2.2); target screen ships with a later session — inert row in S13.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settings_rowNotifications;

  /// F8.1 Notifications row caption, verbatim from the wireframe. S13.
  ///
  /// In en, this message translates to:
  /// **'Per line, off unless you turn them on'**
  String get settings_rowNotificationsCaption;

  /// F8.1 row label; the F8.4 relay-info screen ships with a later session — inert row in S13.
  ///
  /// In en, this message translates to:
  /// **'Relay'**
  String get settings_rowRelay;

  /// F8.1 Relay row caption — the relay host name. NEVER TRANSLATE: identical in every locale (it is an address, not copy). S13.
  ///
  /// In en, this message translates to:
  /// **'relay.nimna.app'**
  String get settings_rowRelayCaption;

  /// F8.1 row label; opens the standard OSS license list. S13.
  ///
  /// In en, this message translates to:
  /// **'Licenses'**
  String get settings_rowLicenses;

  /// F8.1 destructive row label, verbatim; sits apart at the bottom, danger-toned. S13.
  ///
  /// In en, this message translates to:
  /// **'Wipe everything'**
  String get settings_rowWipeEverything;

  /// F8.1 Wipe-everything row caption, verbatim from the wireframe. S13.
  ///
  /// In en, this message translates to:
  /// **'Every line, every message — this phone.'**
  String get settings_rowWipeEverythingCaption;

  /// F8.2 setup headline, verbatim. S13.
  ///
  /// In en, this message translates to:
  /// **'Choose a PIN'**
  String get lock_choosePinTitle;

  /// F8.2 setup caption, verbatim — the zero-leak promise stated where the lock is set. S13.
  ///
  /// In en, this message translates to:
  /// **'When locked, the screen shows only the symbol and this pad. Nothing else — not even how many lines you have.'**
  String get lock_choosePinCaption;

  /// PROVISIONAL (S13 CODE, flagged for the design loop): F8.2 specifies 'PIN entered twice (confirm step, same frame pattern)' but carries no confirm-step headline. Voice register: short, plain, no scolding.
  ///
  /// In en, this message translates to:
  /// **'Enter it again'**
  String get lock_confirmPinTitle;

  /// PROVISIONAL (S13 CODE, flagged for the design loop): confirm-step mismatch line; no artifact carries one. Follows the error register: state what happened and what to do, never blame.
  ///
  /// In en, this message translates to:
  /// **'Those didn\'t match — start again.'**
  String get lock_confirmPinMismatch;

  /// PROVISIONAL (S13 CODE, flagged for the design loop): advances Choose-a-PIN to the confirm step. Needed because the pad accepts 4-8 digits (wireframes README) so the choose step cannot auto-submit. Register: buttons are verbs, one or two words.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get lock_actionNext;

  /// PROVISIONAL (S13 CODE, flagged for the design loop): headline of the current-PIN gate required before changing or turning off the lock (F8.2 edge: 'Turning lock OFF later requires the current PIN first').
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN'**
  String get lock_enterPinTitle;

  /// PROVISIONAL (S13 CODE, flagged for the design loop): removes the app lock, offered only after the current PIN is verified. Register: buttons are verbs, one or two words.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get lock_actionTurnOff;

  /// F8.2 biometric toggle label, verbatim. Row hidden when no biometric hardware. NOTE: 'Face ID' is the iOS name; Android naming flagged in progress/SESSION-13.md for the design loop. S13.
  ///
  /// In en, this message translates to:
  /// **'Unlock with Face ID'**
  String get lock_biometricToggleLabel;

  /// F8.2 biometric toggle caption, verbatim. The toggle ships ON in the setup flow (spec section 6: strongly recommended). S13.
  ///
  /// In en, this message translates to:
  /// **'Recommended. Falls back to your PIN.'**
  String get lock_biometricToggleCaption;

  /// F8.2 bottom caption, verbatim — the no-recovery consequence stated at setup time, not discovered later (spec section 6.1). S13.
  ///
  /// In en, this message translates to:
  /// **'There\'s no way to recover a forgotten PIN — there\'s no account to prove you\'re you. Forgetting it means reinstalling, which wipes this phone\'s lines.'**
  String get lock_noRecoveryCaption;

  /// PROVISIONAL (S13 CODE, flagged for the design loop): the OS biometric prompt's purpose line (local_auth localizedReason; iOS pairs with NSFaceIDUsageDescription). Phone-call register, no fear.
  ///
  /// In en, this message translates to:
  /// **'Unlock your lines.'**
  String get lock_biometricPromptReason;

  /// PROVISIONAL (S13 CODE, flagged for the design loop): a11y label for the PIN pad backspace key (screen 12 shows only the glyph).
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get lock_keypadDeleteA11y;

  /// CANONICAL voice string 8 line 1, verbatim. Hi-fi screen 08 renders 'everything' at weight 600 — see wipe_fullTitleEmphasis. S13.
  ///
  /// In en, this message translates to:
  /// **'Wipe everything?'**
  String get wipe_fullTitle;

  /// The substring of wipe_fullTitle rendered at weight 600 (hi-fi screen 08). Must appear verbatim inside wipe_fullTitle in every locale; if absent at runtime the title renders unemphasized. S13.
  ///
  /// In en, this message translates to:
  /// **'everything'**
  String get wipe_fullTitleEmphasis;

  /// CANONICAL voice string 8 body, verbatim. Never edit outside a voice-guide change. S13.
  ///
  /// In en, this message translates to:
  /// **'Keys and messages are destroyed on this phone. There is no backup, anywhere, by design — nothing can bring them back.'**
  String get wipe_fullBody;

  /// Destructive-hold button label, verbatim from hi-fi screen 08 and F7.2/F7.3 (supersedes F8.3's earlier 'Wipe now' label — the hold IS the confirmation). S13.
  ///
  /// In en, this message translates to:
  /// **'Hold to wipe'**
  String get wipe_holdToWipe;

  /// Full-wipe hold caption, verbatim from hi-fi screen 08 (supersedes the F8.3 wireframe wording). 2.5 s is USER-settled (2026-07-03). S13.
  ///
  /// In en, this message translates to:
  /// **'Hold for 2½ seconds. Release to cancel.'**
  String get wipe_fullHoldCaption;

  /// CANONICAL voice string 8 safe action, verbatim — a warm word, never 'Cancel' (voice register notes). S13.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get wipe_actionKeep;

  /// F7.2 per-channel wipe sheet headline, verbatim. The F7 host screen ships with a later session; the sheet is the S13 reusable component. S13.
  ///
  /// In en, this message translates to:
  /// **'Wipe this line?'**
  String get wipe_channelTitle;

  /// F7.2 per-channel wipe sheet body, verbatim. S13.
  ///
  /// In en, this message translates to:
  /// **'Keys and messages for this line are destroyed on this phone. Nothing can bring them back.'**
  String get wipe_channelBody;

  /// F7.2 honest cross-device note, verbatim — prevents a false belief the UI could never correct later. S13.
  ///
  /// In en, this message translates to:
  /// **'Their phone keeps its side unless they wipe too.'**
  String get wipe_channelPeerNote;

  /// F7.2 hold caption, verbatim. 1.5 s is USER-settled (2026-07-03), deliberately shorter than the 2.5 s full wipe. S13.
  ///
  /// In en, this message translates to:
  /// **'Hold for 1.5 seconds. Let go to keep everything.'**
  String get wipe_channelHoldCaption;

  /// CANONICAL toast copy (components.md Toast; F7.2 exit), verbatim. Consumed by the F7 host screen's session; the key lands with the S13 wipe seam.
  ///
  /// In en, this message translates to:
  /// **'Channel wiped.'**
  String get wipe_channelWipedToast;
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
