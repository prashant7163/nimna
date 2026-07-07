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

  @override
  String get settings_title => 'Settings';

  @override
  String get settings_rowAppLock => 'App lock';

  @override
  String get settings_rowAppLockOff =>
      'Off — a PIN or your face, before anything shows';

  @override
  String get settings_rowAppLockOn => 'On';

  @override
  String get settings_rowAppLockOnBiometric => 'On — PIN + Face ID';

  @override
  String get settings_rowNotifications => 'Notifications';

  @override
  String get settings_rowNotificationsCaption =>
      'Per line, off unless you turn them on';

  @override
  String get settings_rowRelay => 'Relay';

  @override
  String get settings_rowRelayCaption => 'relay.nimna.app';

  @override
  String get settings_rowLicenses => 'Licenses';

  @override
  String get settings_rowWipeEverything => 'Wipe everything';

  @override
  String get settings_rowWipeEverythingCaption =>
      'Every line, every message — this phone.';

  @override
  String get lock_choosePinTitle => 'Choose a PIN';

  @override
  String get lock_choosePinCaption =>
      'When locked, the screen shows only the symbol and this pad. Nothing else — not even how many lines you have.';

  @override
  String get lock_confirmPinTitle => 'Enter it again';

  @override
  String get lock_confirmPinMismatch => 'Those didn\'t match — start again.';

  @override
  String get lock_actionNext => 'Next';

  @override
  String get lock_enterPinTitle => 'Enter your PIN';

  @override
  String get lock_actionTurnOff => 'Turn off';

  @override
  String get lock_biometricToggleLabel => 'Unlock with Face ID';

  @override
  String get lock_biometricToggleCaption =>
      'Recommended. Falls back to your PIN.';

  @override
  String get lock_noRecoveryCaption =>
      'There\'s no way to recover a forgotten PIN — there\'s no account to prove you\'re you. Forgetting it means reinstalling, which wipes this phone\'s lines.';

  @override
  String get lock_biometricPromptReason => 'Unlock your lines.';

  @override
  String get lock_keypadDeleteA11y => 'Delete';

  @override
  String get wipe_fullTitle => 'Wipe everything?';

  @override
  String get wipe_fullTitleEmphasis => 'everything';

  @override
  String get wipe_fullBody =>
      'Keys and messages are destroyed on this phone. There is no backup, anywhere, by design — nothing can bring them back.';

  @override
  String get wipe_holdToWipe => 'Hold to wipe';

  @override
  String get wipe_fullHoldCaption => 'Hold for 2½ seconds. Release to cancel.';

  @override
  String get wipe_actionKeep => 'Keep';

  @override
  String get wipe_channelTitle => 'Wipe this line?';

  @override
  String get wipe_channelBody =>
      'Keys and messages for this line are destroyed on this phone. Nothing can bring them back.';

  @override
  String get wipe_channelPeerNote =>
      'Their phone keeps its side unless they wipe too.';

  @override
  String get wipe_channelHoldCaption =>
      'Hold for 1.5 seconds. Let go to keep everything.';

  @override
  String get wipe_channelWipedToast => 'Channel wiped.';

  @override
  String get billing_headline => 'One of you buys the line.';

  @override
  String get billing_subhead => 'The other never pays.';

  @override
  String get billing_pointSubscriptionTitle => 'One subscription a year.';

  @override
  String get billing_pointSubscriptionCaption =>
      'As many lines as you care to create.';

  @override
  String get billing_pointPermanenceTitle => 'Every line is yours for good.';

  @override
  String get billing_pointPermanenceCaption =>
      'If it lapses, everything you made keeps working — only new lines wait.';

  @override
  String get billing_pointNoAccountTitle => 'No account.';

  @override
  String get billing_pointNoAccountCaption =>
      'The receipt stays between you and the store.';

  @override
  String get billing_pointJoiningFreeTitle => 'Joining is always free.';

  @override
  String get billing_pointJoiningFreeCaption =>
      'The person you invite never sees this screen.';

  @override
  String billing_ctaStart(String price) {
    return '$price — start';
  }

  @override
  String get billing_restore => 'Restore';

  @override
  String get billing_noIdentityFootnote => 'We never learn who you are.';

  @override
  String get billing_restoreChecking => 'Checking with the store…';

  @override
  String get billing_restoreSuccessToast => 'Purchase restored.';

  @override
  String get billing_subscriptionStartedToast => 'Subscription started.';

  @override
  String get billing_restoreNothing =>
      'The store has no subscription for this account.';

  @override
  String get billing_storeUnreachable =>
      'Couldn\'t reach the store. Try again in a moment.';

  @override
  String get billing_reconnectToVerify =>
      'Reconnect to verify your subscription.';

  @override
  String get billing_tryAgain => 'Try again';

  @override
  String billing_autoRenewDisclosure(String store) {
    return 'One yearly subscription. It renews on its own and charges your $store account until you cancel — anytime, in your account settings. Lines you\'ve already made stay yours either way.';
  }

  @override
  String get billing_termsLabel => 'Terms of Use';

  @override
  String get billing_privacyLabel => 'Privacy Policy';
}
