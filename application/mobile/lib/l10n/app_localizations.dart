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

  /// F2 flow title (hi-fi 02-create-code navbar; also the F2.1 heading and its primary action — voice register: buttons are verbs, one or two words).
  ///
  /// In en, this message translates to:
  /// **'Create a code'**
  String get pairing_createTitle;

  /// F2.1 body copy, wireframe verbatim.
  ///
  /// In en, this message translates to:
  /// **'A code pairs your phone with one other. Share it however you like — in person is safest.'**
  String get pairing_createIntro;

  /// F2.1 TTL row label, wireframe verbatim.
  ///
  /// In en, this message translates to:
  /// **'Code works for'**
  String get pairing_ttlLabel;

  /// F2.1 TTL row caption, wireframe verbatim.
  ///
  /// In en, this message translates to:
  /// **'Shorter is safer. One use, either way.'**
  String get pairing_ttlHint;

  /// TTL preset value rendering (1 hour / 8 hours / 24 hours — S8 intake section 5 presets). Locale-aware plural; at the 24 h default this renders '24 hours' exactly as the wireframe shows.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{1 hour} other{{hours} hours}}'**
  String pairing_ttlHours(int hours);

  /// F2.1 offline edge, wireframe verbatim. Nothing is generated without a live registration — no phantom codes.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. A code needs the relay listening for it — try again when you\'re connected.'**
  String get pairing_offlineError;

  /// CANONICAL, spec section 3.1 verbatim (voice string 13). The one-line briefing that rides every code share: the F2.3 sheet's header caption and the share-screen caption. '24h' is spec-fixed wording here regardless of the chosen TTL preset — never edit outside a spec change.
  ///
  /// In en, this message translates to:
  /// **'Works once, expires in 24h — share it like a password.'**
  String get pairing_shareBriefing;

  /// Share-screen caption line 2 (hi-fi 02-create-code verbatim): text code and QR are one surface, each independently shareable (spec section 3.1.1).
  ///
  /// In en, this message translates to:
  /// **'The words or the square — either one pairs you.'**
  String get pairing_eitherFormPairs;

  /// Share-screen secondary action: puts the display-form code on the clipboard (hi-fi 02-create-code).
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get pairing_copyAction;

  /// Share-screen secondary action: opens the F2.3 share sheet (hi-fi 02-create-code, ellipsis included).
  ///
  /// In en, this message translates to:
  /// **'Share…'**
  String get pairing_shareAction;

  /// Toast after Copy (F2.2 / components.md toast examples, verbatim). Auto-dismiss 3 s.
  ///
  /// In en, this message translates to:
  /// **'Code copied.'**
  String get pairing_codeCopiedToast;

  /// F2.3 sheet option, wireframe verbatim. The code travels alone as XXX-XXX-XXX text.
  ///
  /// In en, this message translates to:
  /// **'Share the code as text'**
  String get pairing_shareAsText;

  /// F2.3 sheet option, wireframe verbatim. The QR PNG travels alone; temp file deleted after handoff.
  ///
  /// In en, this message translates to:
  /// **'Share the QR as an image'**
  String get pairing_shareQrAsImage;

  /// F2.3 sheet ghost option, wireframe verbatim.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get pairing_copyCode;

  /// F2.4 waiting caption under the dotted idle line, wireframe + hi-fi verbatim.
  ///
  /// In en, this message translates to:
  /// **'Waiting for them to join…'**
  String get pairing_waitingForJoin;

  /// F2.4 patience caption. Wireframe verbatim at the 24 h default ('Your code works for 24 hours — …'); the hour count follows the chosen TTL preset for claim accuracy. Promises the code's LIFETIME, never background presence (USER copy decision 2026-07-04): no push, no background socket claim.
  ///
  /// In en, this message translates to:
  /// **'Your code works for {hours, plural, =1{1 hour} other{{hours} hours}} — come back anytime. Pairing completes when you\'re both here.'**
  String pairing_waitLifetime(int hours);

  /// F2.4 ghost action, wireframe verbatim: discards code and keypair — nothing was created. Also the confirming action of the back-confirm modal.
  ///
  /// In en, this message translates to:
  /// **'Cancel this code'**
  String get pairing_cancelCode;

  /// Back-from-waiting confirm copy (F2.2 exit annotation, wireframe verbatim).
  ///
  /// In en, this message translates to:
  /// **'Stop waiting? The code stops working.'**
  String get pairing_stopWaitingConfirm;

  /// Ghost decline (F2.8/F2.9 wireframe verbatim; voice register ghost vocabulary). Also the safe choice on the back-confirm modal.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get pairing_notNow;

  /// F2.8 edge headline, wireframe verbatim. Silence doctrine: expiry is the only failure surfaced, and only to the creator.
  ///
  /// In en, this message translates to:
  /// **'This code expired unused.'**
  String get pairing_expiredHeadline;

  /// F2.8 edge body, wireframe verbatim — expiry means literally nothing happened; no channel, no residue.
  ///
  /// In en, this message translates to:
  /// **'Nothing was created. Make a new one whenever you\'re ready.'**
  String get pairing_expiredBody;

  /// F2.8 primary action, wireframe verbatim: back to F2.1 (fresh keypair, fresh code).
  ///
  /// In en, this message translates to:
  /// **'Make a new code'**
  String get pairing_makeNewCode;

  /// F2.5 edge-case copy, wireframe verbatim: the bridge/handshake window failed (connection lost). Both sides discard partial state; a half-made channel never exists (spec section 3.1.6).
  ///
  /// In en, this message translates to:
  /// **'That didn\'t finish. The code is spent — make a new one.'**
  String get pairing_spentBody;
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
