// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

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
  String get pairing_joinTitle => 'Enter a code';

  @override
  String get pairing_joinIntro =>
      'Codes come from the other person. Each one works once.';

  @override
  String get pairing_joinPaste => 'Paste';

  @override
  String get pairing_joinScan => 'Scan';

  @override
  String get pairing_joinUpload => 'Upload';

  @override
  String get pairing_joinAction => 'Join';

  @override
  String get pairing_joinOffline =>
      'You\'re offline. Joining needs a connection.';

  @override
  String get pairing_joinScanTitle => 'Scan their code';

  @override
  String get pairing_joinScanCaption =>
      'Point your camera at the code on their screen.';

  @override
  String get pairing_joinScanEnterInstead => 'Enter it instead';

  @override
  String get pairing_joinCameraDenied =>
      'No camera access — type the code instead.';

  @override
  String get pairing_joinNoQrInFile => 'No code in that file.';

  @override
  String get pairing_joinFoundThem => 'Found them.';

  @override
  String get pairing_joinSettingUp => 'Setting up the line…';

  @override
  String get pairing_joinCodeSpentNote =>
      'The code has done its job. It won\'t work again for anyone.';

  @override
  String get pairing_joinSpentBody =>
      'That didn\'t finish. The code is spent — ask them to make a new one.';

  @override
  String get pairing_noMatchError =>
      'That code didn\'t match anything. Codes expire — ask them to make a new one.';

  @override
  String get pairing_clearAction => 'Clear';

  @override
  String get pairing_verifyTitle => 'Call them and compare';

  @override
  String get pairing_verifyBody =>
      'Read these three words to each other. If they match, the line is yours alone.';

  @override
  String get pairing_verifyMatch => 'They match';

  @override
  String get pairing_verifyMismatch => 'They don\'t match';

  @override
  String get pairing_mismatchTitle => 'The words didn\'t match.';

  @override
  String get pairing_mismatchBody =>
      'That can mean someone got between you while pairing. This pairing has been thrown away — nothing was kept.';

  @override
  String get pairing_mismatchShareSafer =>
      'Make a new code and share it somewhere safer. In person is safest.';

  @override
  String get pairing_readyTitle => 'The line is yours.';

  @override
  String get pairing_nameLineLabel => 'Name this line';

  @override
  String get pairing_nameLineCaption =>
      'Labels live only on this phone. They\'re never sent anywhere.';

  @override
  String get pairing_doneAction => 'Done';

  @override
  String get pairing_goBack => 'Go back';

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

  @override
  String get session_lineOnline => 'On the line';

  @override
  String get session_lineOffline => 'Not on the line';

  @override
  String get session_lineLost => 'The line dropped.';

  @override
  String get session_lineDropped => 'The line dropped. Trying to reconnect…';

  @override
  String get session_lineRecovered => 'You\'re both here.';

  @override
  String get session_peerHungUp => 'They hung up.';

  @override
  String get session_youHungUp => 'You hung up.';

  @override
  String get chat_hangUp => 'Hang up';

  @override
  String get chat_waitingHeader => 'WAITING — ON YOUR PHONE ONLY';

  @override
  String get chat_peerOfflineHeadline => 'They\'re not on the line right now.';

  @override
  String get chat_peerOfflineBody =>
      'Anything you write waits here — on your phone only — and goes through when you\'re both on.';

  @override
  String get chat_expiryDisclaimer =>
      'Their app will delete this on schedule, and yours will too.\nA timer can\'t undo being read — a screenshot is still a screenshot. It\'s a courtesy between the two of you, not a guarantee.';

  @override
  String get chat_timerOff => 'Off';

  @override
  String chat_timerMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes min',
      one: '1 min',
    );
    return '$_temp0';
  }

  @override
  String chat_timerHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hr',
      one: '1 hr',
    );
    return '$_temp0';
  }

  @override
  String get chat_timerButtonA11y => 'Disappearing timer';

  @override
  String get chat_composerA11y => 'Message';

  @override
  String get chat_sendA11y => 'Send';

  @override
  String get chat_deliveryWaitingA11y => 'Waiting. On your phone only.';

  @override
  String get chat_deliverySentA11y => 'Sent.';

  @override
  String get chat_deliveryDeliveredA11y => 'Delivered.';

  @override
  String get media_attachA11y => 'Add a photo or file';

  @override
  String get media_pickPhoto => 'Photo';

  @override
  String get media_pickFile => 'File';

  @override
  String get media_overCapError =>
      'That\'s over 5 MB — the line carries documents, not archives. Try a smaller file.';

  @override
  String get media_metadataStripNotice =>
      'Photos are cleaned before they\'re sealed — location, device, and time are stripped on your phone, before encryption.';

  @override
  String get media_compressionNote =>
      'Sent smaller by default. Original quality is a toggle away.';

  @override
  String get media_originalQualityToggle => 'Original quality';

  @override
  String get media_exportAction => 'Export';

  @override
  String get media_exportConfirm =>
      'This copies it out of Nimna — into your phone\'s own storage.';

  @override
  String get media_exportRollNote =>
      'Nothing you receive touches your photo roll. It stays inside Nimna until you choose to take it out.';

  @override
  String get media_exportCancel => 'Go back';

  @override
  String media_viewerReceivedTime(String time) {
    return 'Received $time';
  }

  @override
  String get media_sendingA11y => 'Sending.';

  @override
  String get media_receivingA11y => 'Receiving.';

  @override
  String get media_documentA11y => 'Document.';

  @override
  String get media_imageA11y => 'Photo.';

  @override
  String get media_documentKindPdf => 'PDF';

  @override
  String get media_documentKindFile => 'File';

  @override
  String media_sizeMegabytes(String size) {
    return '$size MB';
  }

  @override
  String media_sizeKilobytes(String size) {
    return '$size KB';
  }

  @override
  String media_documentMeta(String kind, String size) {
    return '$kind · $size';
  }

  @override
  String get knock_waitingTitle =>
      'Knocked. If they pick up in the next minute, the line opens.';

  @override
  String get knock_waitingCaption =>
      'One knock is enough — it won\'t repeat on its own.';

  @override
  String get knock_noAnswer => 'No answer.';

  @override
  String get knock_again => 'Knock again';

  @override
  String get knock_staleHint =>
      'No answer in a while. If they lost their phone, this line can\'t come back — you\'d pair again with a new code.';

  @override
  String knock_incomingKnocking(String label) {
    return '$label is knocking.';
  }

  @override
  String get knock_pickUp => 'Pick up';

  @override
  String get knock_ignore => 'Ignore';

  @override
  String get push_toggleLabel => 'Notify me when they knock';

  @override
  String get push_tradeOff =>
      'Off: nothing about this line ever touches Apple or Google.';

  @override
  String get push_tradeOn =>
      'On: a knock can wake this phone through their notification service, carrying two words — \"New activity.\" No line, no name, no message — and the relay forgets the address the moment it\'s used.';

  @override
  String get push_newActivityBody => 'New activity';

  @override
  String get channelSettings_subtitle => 'Line settings — this phone only';
}
