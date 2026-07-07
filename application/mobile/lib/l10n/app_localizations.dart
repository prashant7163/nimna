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

  /// F3.1 join-screen headline, verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'Enter a code'**
  String get pairing_joinTitle;

  /// F3.1 join-screen caption, verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'Codes come from the other person. Each one works once.'**
  String get pairing_joinIntro;

  /// F3.1 quiet affordance — paste the code from the clipboard (join method ii). Verb, verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get pairing_joinPaste;

  /// F3.1 quiet affordance — open the live QR scanner (join method iii). Verb, verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get pairing_joinScan;

  /// F3.1 quiet affordance — pick a QR image or PDF (join method iv). Verb, verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get pairing_joinUpload;

  /// F3.1 primary button — begin joining with the entered code. Enabled only when the code is complete and is not this device's own. Verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get pairing_joinAction;

  /// F3.1 edge — device offline; nothing was sent. Verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Joining needs a connection.'**
  String get pairing_joinOffline;

  /// F3.2 live-scanner headline, verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'Scan their code'**
  String get pairing_joinScanTitle;

  /// F3.2 live-scanner caption, verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'Point your camera at the code on their screen.'**
  String get pairing_joinScanCaption;

  /// F3.2 escape from the scanner back to manual entry. Verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'Enter it instead'**
  String get pairing_joinScanEnterInstead;

  /// F3.2 edge — camera permission denied; drop to manual entry (or upload). Verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'No camera access — type the code instead.'**
  String get pairing_joinCameraDenied;

  /// F3.1 edge — an uploaded image/PDF held no readable QR; field untouched. Verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'No code in that file.'**
  String get pairing_joinNoQrInFile;

  /// F3.3 handshake headline — the bridge formed. Verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'Found them.'**
  String get pairing_joinFoundThem;

  /// F3.3 handshake status line — key agreement runs beneath; usually sub-second. Verbatim. No crypto vocabulary. S9.
  ///
  /// In en, this message translates to:
  /// **'Setting up the line…'**
  String get pairing_joinSettingUp;

  /// F3.3 footer — the single-use code is discarded forever the moment pairing completes (spec §3.1.6). Verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'The code has done its job. It won\'t work again for anyone.'**
  String get pairing_joinCodeSpentNote;

  /// F3.3 edge — the handshake/bridge failed (connection lost); both sides discarded partial state, a half-made channel never exists (spec §3.1.6). Verbatim. Distinct from the creator's F2.5 '…make a new one.' by the 'ask them' (the joiner cannot create a code). S9.
  ///
  /// In en, this message translates to:
  /// **'That didn\'t finish. The code is spent — ask them to make a new one.'**
  String get pairing_joinSpentBody;

  /// CANONICAL, voice guide string (register notes) verbatim. F3.6/F3.7 — the ONE generic response for wrong / expired / used / never-existed codes (indistinguishable by design so a prober can never confirm a code once existed; spec §3.1.6, silence doctrine). Shown after the joiner's own no-answer timeout. Never edit outside a spec/voice change. S9.
  ///
  /// In en, this message translates to:
  /// **'That code didn\'t match anything. Codes expire — ask them to make a new one.'**
  String get pairing_noMatchError;

  /// F3.6/F3.8 — clears the code field to try again. Verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get pairing_clearAction;

  /// F3.4 safety-phrase headline — the closing ritual of pairing, compared out-of-band (spec §3.1 verification). Verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'Call them and compare'**
  String get pairing_verifyTitle;

  /// F3.4 safety-phrase body, verbatim (voice guide string on the closing ritual). S9.
  ///
  /// In en, this message translates to:
  /// **'Read these three words to each other. If they match, the line is yours alone.'**
  String get pairing_verifyBody;

  /// F3.4 primary button — the phrases matched; finalize (spec §3.1). No skip affordance (USER 2026-07-04). Verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'They match'**
  String get pairing_verifyMatch;

  /// F3.4 secondary (spaced below, never adjacent) — decline; the pairing is thrown away locally, no peer signal (USER 2026-07-07). Verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'They don\'t match'**
  String get pairing_verifyMismatch;

  /// F2.9/F3.4-decline mismatch screen headline, verbatim. Level tone — the MITM defense working as designed (spec §3.1 verification, §9). S9.
  ///
  /// In en, this message translates to:
  /// **'The words didn\'t match.'**
  String get pairing_mismatchTitle;

  /// F2.9/F3.4-decline mismatch screen body, verbatim. States what it can mean and that everything was discarded LOCALLY — it never claims the other side was notified (silence doctrine; USER 2026-07-07 local-only discard). S9.
  ///
  /// In en, this message translates to:
  /// **'That can mean someone got between you while pairing. This pairing has been thrown away — nothing was kept.'**
  String get pairing_mismatchBody;

  /// F2.9/F3.4-decline mismatch screen forward guidance, verbatim. Points to a fresh, safer pairing. S9. NOTE (design-sync flag): the 'make a new code' phrasing is creator-oriented; on the joiner side the forward action is to ask the other person for a fresh code — flagged in progress/SESSION-9.md.
  ///
  /// In en, this message translates to:
  /// **'Make a new code and share it somewhere safer. In person is safest.'**
  String get pairing_mismatchShareSafer;

  /// F3.5 channel-ready headline, verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'The line is yours.'**
  String get pairing_readyTitle;

  /// F3.5 label-field caption — the label is local-only. Verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'Name this line'**
  String get pairing_nameLineLabel;

  /// F3.5 honest note — labels are local text, never transmitted (spec §6). Verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'Labels live only on this phone. They\'re never sent anywhere.'**
  String get pairing_nameLineCaption;

  /// F3.5 primary button — persist the channel and enter the line. Verbatim. S9.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get pairing_doneAction;

  /// Canonical button verb (voice guide register notes). Dismisses the mismatch screen back to the channel list. S9.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get pairing_goBack;

  /// F9.2 paywall headline (hi-fi screen 09 .display, verbatim; voice string 9 line 1). NO price number ever appears in copy (spec §10 numberless lock).
  ///
  /// In en, this message translates to:
  /// **'One of you buys the line.'**
  String get billing_headline;

  /// F9.2 paywall sub-headline (hi-fi screen 09 .bodyLg, verbatim; voice string 9 line 1). The receiver-never-pays half of the asymmetry.
  ///
  /// In en, this message translates to:
  /// **'The other never pays.'**
  String get billing_subhead;

  /// Paywall feature 1 title (hi-fi screen 09, verbatim). Condenses voice string 9's 'one yearly subscription'. No number, per the numberless lock.
  ///
  /// In en, this message translates to:
  /// **'One subscription a year.'**
  String get billing_pointSubscriptionTitle;

  /// Paywall feature 1 caption (hi-fi screen 09, verbatim). Unlimited channel creation while subscribed (spec §10).
  ///
  /// In en, this message translates to:
  /// **'As many lines as you care to create.'**
  String get billing_pointSubscriptionCaption;

  /// Paywall feature 2 title (hi-fi screen 09, verbatim). THE permanence guarantee at headline prominence, never fine print (spec §10).
  ///
  /// In en, this message translates to:
  /// **'Every line is yours for good.'**
  String get billing_pointPermanenceTitle;

  /// Paywall feature 2 caption (hi-fi screen 09, verbatim). A lapse gates creation of NEW lines only; existing lines work forever (spec §10).
  ///
  /// In en, this message translates to:
  /// **'If it lapses, everything you made keeps working — only new lines wait.'**
  String get billing_pointPermanenceCaption;

  /// Paywall feature 3 title (hi-fi screen 09, verbatim). Never 'anonymous' (account-less ≠ anonymity — voice word-ban).
  ///
  /// In en, this message translates to:
  /// **'No account.'**
  String get billing_pointNoAccountTitle;

  /// Paywall feature 3 caption (hi-fi screen 09, verbatim). Store-mediated, no Nimna identity (spec §10).
  ///
  /// In en, this message translates to:
  /// **'The receipt stays between you and the store.'**
  String get billing_pointNoAccountCaption;

  /// Paywall feature 4 title (hi-fi screen 09, verbatim). Receivers are never paywalled (spec §10).
  ///
  /// In en, this message translates to:
  /// **'Joining is always free.'**
  String get billing_pointJoiningFreeTitle;

  /// Paywall feature 4 caption (hi-fi screen 09, verbatim).
  ///
  /// In en, this message translates to:
  /// **'The person you invite never sees this screen.'**
  String get billing_pointJoiningFreeCaption;

  /// F9.2 primary CTA (hi-fi screen 09 '{STORE_PRICE} — start'). {price} is the store's localized price string (ProductDetails.price) — NEVER a hardcoded number (spec §10 numberless lock). The em-dash and 'start' are the fixed copy around it.
  ///
  /// In en, this message translates to:
  /// **'{price} — start'**
  String billing_ctaStart(String price);

  /// F9.2 ghost action (hi-fi screen 09, verbatim). Store-mediated restore — the only path to creation after reinstall/wipe (spec §10). Paywall-only; no in-app status screen (USER 2026-07-07).
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get billing_restore;

  /// F9.2 closing micro line (hi-fi screen 09 .micro, verbatim; voice string 9 tail).
  ///
  /// In en, this message translates to:
  /// **'We never learn who you are.'**
  String get billing_noIdentityFootnote;

  /// F9.5 in-progress caption while restore runs (wireframe f9 verbatim). Ellipsis included.
  ///
  /// In en, this message translates to:
  /// **'Checking with the store…'**
  String get billing_restoreChecking;

  /// CANONICAL toast (components.md Toast; F9.5 verbatim). Shown on successful restore, then creation proceeds. Auto-dismiss 3 s.
  ///
  /// In en, this message translates to:
  /// **'Purchase restored.'**
  String get billing_restoreSuccessToast;

  /// F9.4 toast after a successful purchase (wireframe f9 verbatim), then the create flow opens. No celebration screen — the reward is being where you were going. Auto-dismiss 3 s.
  ///
  /// In en, this message translates to:
  /// **'Subscription started.'**
  String get billing_subscriptionStartedToast;

  /// F9.5 factual one-liner when restore finds nothing (wireframe f9 verbatim). Stays on the page, no drama; the CTA remains available.
  ///
  /// In en, this message translates to:
  /// **'The store has no subscription for this account.'**
  String get billing_restoreNothing;

  /// F9.5 edge when the store can't be reached during restore (wireframe f9 verbatim).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the store. Try again in a moment.'**
  String get billing_storeUnreachable;

  /// Fail-closed offline paywall state (CODE decision, SESSION-17): when the platform entitlement query can't resolve, the paywall shows this calm line instead of the buy CTA. It never blocks USING existing channels — only creation. On-voice; PM-reviewable at S16.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to verify your subscription.'**
  String get billing_reconnectToVerify;

  /// Retry affordance on the fail-closed offline paywall state (re-runs the entitlement query). Functional verb, voice register (buttons are verbs). PM-reviewable at S16.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get billing_tryAgain;

  /// Store-mandated auto-renew disclosure shown near the F9.2 CTA — renewal terms, charges the store account, how to cancel, plus the permanence reassurance. USER-approved 2026-07-07 12:39 (Option A + permanence). Contains NO price number (numberless lock). {store} is the platform store brand name, resolved at runtime (App Store on iOS / Google Play on Android) — a non-translated proper noun. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'One yearly subscription. It renews on its own and charges your {store} account until you cancel — anytime, in your account settings. Lines you\'ve already made stay yours either way.'**
  String billing_autoRenewDisclosure(String store);

  /// Final label — link affordance near the F9.2 CTA (store-mandated Terms of Use / EULA), part of the disclosure block. Destination lands at S19 (website TODO). Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Terms of Use'**
  String get billing_termsLabel;

  /// Final label — link affordance near the F9.2 CTA (store-mandated Privacy Policy), part of the disclosure block. Destination lands at S19 (website TODO). Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get billing_privacyLabel;

  /// Session-status-line label when the live session is up (components.md session-status-indicator; wireframe F5.4 'On the line'). S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'On the line'**
  String get session_lineOnline;

  /// Session-status-line label when there is no live session (components.md session-status-indicator; wireframe F5.1/F5.12 'Not on the line'). S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Not on the line'**
  String get session_lineOffline;

  /// Voice guide string 10 — truthful terminal caption for a mid-session connection loss with NO reconnect in flight (bridge died without an authenticated HANGUP; the terminal SessionLineState.connectionLost). Canonical subset. The reconnecting variant is session_lineDropped, rendered only while a reconnect attempt is live (S12). S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'The line dropped.'**
  String get session_lineLost;

  /// Voice guide string 10, line 1 — the reconnecting caption, rendered only while a reconnect attempt is genuinely in flight (SessionLineState.reconnecting, wired S12). Not rendered in S10 — see session_lineLost for the terminal no-reconnect caption. Canonical, verbatim. The ellipsis is a single U+2026 character. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'The line dropped. Trying to reconnect…'**
  String get session_lineDropped;

  /// Voice guide string 10, line 2 — shown on reconnect recovery (wireframe F5.15), rendered only once reconnect exists (S12). Not rendered in S10. Canonical, verbatim. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'You\'re both here.'**
  String get session_lineRecovered;

  /// Voice guide string 22 — the line-state caption after the peer ends with an authenticated HANGUP (spec §3.3; wireframe F5.4/F5.12). Distinct from string 10's bridge-drop. Canonical, verbatim. S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'They hung up.'**
  String get session_peerHungUp;

  /// Voice guide string 22 — the line-state caption after you end the session (wireframe F5.12). Canonical, verbatim. S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'You hung up.'**
  String get session_youHungUp;

  /// Chat header action that ends the live session (voice register verb 'Hang up'). Wireframe F5.3/F5.4 header. S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Hang up'**
  String get chat_hangUp;

  /// components.md chat-bubbles micro overline above the outbox group while the peer is offline (spec §3.4). Rendered in the micro style; the literal is already uppercase. The em dash is U+2014. S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'WAITING — ON YOUR PHONE ONLY'**
  String get chat_waitingHeader;

  /// Voice guide string 5, line 1 — peer-offline compose-to-outbox headline (wireframe F5.1). Canonical, verbatim. S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'They\'re not on the line right now.'**
  String get chat_peerOfflineHeadline;

  /// Voice guide string 5, line 2 — peer-offline compose-to-outbox body (wireframe F5.1). Canonical, verbatim. S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Anything you write waits here — on your phone only — and goes through when you\'re both on.'**
  String get chat_peerOfflineBody;

  /// Voice guide string 7 — the disappearing-message honor-system disclaimer, shown VERBATIM at the timer picker (wireframe F5.11; components.md). Canonical, verbatim — never softened. The line break separates the two sentences as designed; the em dash is U+2014. S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Their app will delete this on schedule, and yours will too.\nA timer can\'t undo being read — a screenshot is still a screenshot. It\'s a courtesy between the two of you, not a guarantee.'**
  String get chat_expiryDisclaimer;

  /// Disappearing-timer preset: no expiry (USER-locked preset set Off/1min/15min/1hr/24hr; wireframe F5.11). S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get chat_timerOff;

  /// Disappearing-timer preset label in minutes (1 min, 15 min) — locale-aware plural (wireframe F5.11). S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{1 min} other{{minutes} min}}'**
  String chat_timerMinutes(int minutes);

  /// Disappearing-timer preset label in hours (1 hr, 24 hr) — locale-aware plural (wireframe F5.11). S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{1 hr} other{{hours} hr}}'**
  String chat_timerHours(int hours);

  /// A11y label for the composer's timer affordance (the ◷ glyph) that opens the preset picker (wireframe F5.11). Functional label. S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Disappearing timer'**
  String get chat_timerButtonA11y;

  /// A11y label for the composer text field. Functional label. S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get chat_composerA11y;

  /// A11y label for the composer send affordance (the ↑ glyph). Functional label; voice register verb. S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chat_sendA11y;

  /// A11y label for a message in the waiting (local-only outbox) delivery state (components.md chat-bubbles; spec §3.4). Functional label. S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Waiting. On your phone only.'**
  String get chat_deliveryWaitingA11y;

  /// A11y label for a message that has left this phone but is not yet ACKed (components.md chat-bubbles delivery states). Functional label. S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Sent.'**
  String get chat_deliverySentA11y;

  /// A11y label for a message the peer has ACKed (spec §3.3 client ACK; components.md delivery states — the ✓ glyph). Functional label. S10 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Delivered.'**
  String get chat_deliveryDeliveredA11y;

  /// A11y label for the composer's attach affordance (the plus glyph left of the input; components.md media bubbles). Functional label. S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Add a photo or file'**
  String get media_attachA11y;

  /// Attach sheet option — pick a photo (components.md attach affordance: photo / file pickers). S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get media_pickPhoto;

  /// Attach sheet option — pick a document/file (components.md attach affordance: photo / file pickers). S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get media_pickFile;

  /// Over-the-cap error at attach time (voice string 17, canonical verbatim; spec §5.1 5 MB cap). Must stay claim-accurate in translation. S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'That\'s over 5 MB — the line carries documents, not archives. Try a smaller file.'**
  String get media_overCapError;

  /// The metadata-strip feature notice under the attach preview, first time (voice string 17, canonical verbatim; spec §5.1). Marketed as a feature. Must stay claim-accurate (on-device, before encryption). S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Photos are cleaned before they\'re sealed — location, device, and time are stripped on your phone, before encryption.'**
  String get media_metadataStripNotice;

  /// Compression-default helper text beside the original-quality toggle (voice string 17, canonical verbatim; spec §5.1). S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Sent smaller by default. Original quality is a toggle away.'**
  String get media_compressionNote;

  /// Attach-preview toggle label — send at original quality (off by default; components.md attach affordance). Functional label. S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Original quality'**
  String get media_originalQualityToggle;

  /// Media viewer bottom-bar action and export-confirm CTA — the single deliberate act that moves a file out of Nimna's store (components.md media viewer; spec §5.1). Register verb. S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get media_exportAction;

  /// Export-confirm sheet body (components.md media viewer, canonical verbatim; spec §5.1 export is a deliberate act). Must stay claim-accurate. S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'This copies it out of Nimna — into your phone\'s own storage.'**
  String get media_exportConfirm;

  /// Received-media note (voice string 17/16, canonical verbatim; spec §5.1 no auto-save to gallery). Must stay claim-accurate. S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Nothing you receive touches your photo roll. It stays inside Nimna until you choose to take it out.'**
  String get media_exportRollNote;

  /// The safe choice on the export-confirm sheet — a warm register verb, not 'Cancel' (voice register notes; matches string 14's 'Go back'). S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get media_exportCancel;

  /// Media viewer top-bar received-time label (components.md media viewer). {time} is a locale-aware formatted date/time computed via intl. S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Received {time}'**
  String media_viewerReceivedTime(String time);

  /// A11y label for a media bubble in the sending (outbound chunked transfer) state (components.md media bubbles). Functional label. S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Sending.'**
  String get media_sendingA11y;

  /// A11y label for a media bubble in the receiving (inbound chunked transfer) state (components.md media bubbles). Functional label. S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Receiving.'**
  String get media_receivingA11y;

  /// A11y label for a document (non-image) media bubble (components.md media bubbles). Functional label. S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Document.'**
  String get media_documentA11y;

  /// A11y label for an image media bubble (components.md media bubbles). Functional label. S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'Photo.'**
  String get media_imageA11y;

  /// Document-bubble kind label for a PDF attachment (components.md media bubbles: size + kind). Factual file-type label. S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get media_documentKindPdf;

  /// Document-bubble kind label for a non-PDF document attachment (components.md media bubbles: size + kind). Factual file-type label. S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get media_documentKindFile;

  /// Document-bubble file size in megabytes (components.md media bubbles). {size} is a locale-aware formatted number. S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'{size} MB'**
  String media_sizeMegabytes(String size);

  /// Document-bubble file size in kilobytes (components.md media bubbles). {size} is a locale-aware formatted number. S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'{size} KB'**
  String media_sizeKilobytes(String size);

  /// Document-bubble metadata line combining kind and size (components.md media bubbles: 'size + kind'). Composed from media_documentKind* and media_size*. S11 net-new. Enters the S16 crafted-translation pass.
  ///
  /// In en, this message translates to:
  /// **'{kind} · {size}'**
  String media_documentMeta(String kind, String size);
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
