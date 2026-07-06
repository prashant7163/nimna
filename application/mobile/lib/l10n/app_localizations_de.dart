// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

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

  @override
  String get chat_messageActionReply => 'Reply';

  @override
  String get chat_messageActionReact => 'React';

  @override
  String get chat_messageActionDelete => 'Delete';

  @override
  String get chat_replyingToLabel => 'Replying to';

  @override
  String get chat_replyCancelA11y => 'Cancel reply';

  @override
  String get chat_replyTombstone => 'Message no longer available.';

  @override
  String get chat_replyPreviewPhoto => 'Photo';

  @override
  String get chat_replyPreviewDocument => 'Document';

  @override
  String chat_reactionOwnA11y(String emoji) {
    return 'You reacted $emoji. Tap to remove.';
  }

  @override
  String chat_reactionPeerA11y(String emoji) {
    return 'They reacted $emoji.';
  }

  @override
  String get chat_reactionPickMoreA11y => 'Choose another emoji';

  @override
  String get pairing_selfJoinOwnCode =>
      'This is your own Nimna code — share it with the other person.';

  @override
  String get pairing_createTitle => 'Create a code';

  @override
  String get pairing_createIntro =>
      'A code pairs your phone with one other. Share it however you like — in person is safest.';

  @override
  String get pairing_ttlLabel => 'Code works for';

  @override
  String get pairing_ttlHint => 'Shorter is safer. One use, either way.';

  @override
  String pairing_ttlHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hours',
      one: '1 hour',
    );
    return '$_temp0';
  }

  @override
  String get pairing_offlineError =>
      'You\'re offline. A code needs the relay listening for it — try again when you\'re connected.';

  @override
  String get pairing_shareBriefing =>
      'Works once, expires in 24h — share it like a password.';

  @override
  String get pairing_eitherFormPairs =>
      'The words or the square — either one pairs you.';

  @override
  String get pairing_copyAction => 'Copy';

  @override
  String get pairing_shareAction => 'Share…';

  @override
  String get pairing_codeCopiedToast => 'Code copied.';

  @override
  String get pairing_shareAsText => 'Share the code as text';

  @override
  String get pairing_shareQrAsImage => 'Share the QR as an image';

  @override
  String get pairing_copyCode => 'Copy code';

  @override
  String get pairing_waitingForJoin => 'Waiting for them to join…';

  @override
  String pairing_waitLifetime(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hours',
      one: '1 hour',
    );
    return 'Your code works for $_temp0 — come back anytime. Pairing completes when you\'re both here.';
  }

  @override
  String get pairing_cancelCode => 'Cancel this code';

  @override
  String get pairing_stopWaitingConfirm =>
      'Stop waiting? The code stops working.';

  @override
  String get pairing_notNow => 'Not now';

  @override
  String get pairing_expiredHeadline => 'This code expired unused.';

  @override
  String get pairing_expiredBody =>
      'Nothing was created. Make a new one whenever you\'re ready.';

  @override
  String get pairing_makeNewCode => 'Make a new code';

  @override
  String get pairing_spentBody =>
      'That didn\'t finish. The code is spent — make a new one.';
}
