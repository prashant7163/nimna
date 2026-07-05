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
}
