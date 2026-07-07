import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/l10n/app_localizations.dart';
import 'package:nimna/l10n/app_localizations_en.dart';
import 'package:nimna/src/app/theme.dart';
import 'package:nimna/src/domain/models/message_record.dart';
import 'package:nimna/src/session/chat/composer.dart';
import 'package:nimna/src/session/chat/message_actions.dart';
import 'package:nimna/src/session/chat/message_bubble.dart';
import 'package:nimna/src/session/model/message_view.dart';

/// Chat widgets (S10) — bubbles/delivery states, reaction chips + the REQUIRED
/// a11y emoji sanitization, the message-actions card presets, quoted-reply +
/// tombstone, the composer expiry picker (voice string 7 VERBATIM), and the
/// silent typing glyph. BINDING to designs/system/components.md.
void main() {
  final en = AppLocalizationsEn();

  Uint8List id(int seed) => Uint8List.fromList(List.filled(16, seed));

  Widget host(Widget child, {Locale locale = const Locale('en')}) {
    return MaterialApp(
      locale: locale,
      theme: nimnaTheme(Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  MessageView msg({
    required bool outbound,
    String? text = 'hello',
    DeliveryState delivery = DeliveryState.delivered,
    ReplyPreview? reply,
    String? ownReaction,
    String? peerReaction,
    int seed = 1,
  }) => MessageView(
    recordId: id(seed),
    msgId: id(seed + 100),
    outbound: outbound,
    type: MessageType.text,
    timestampMs: 0,
    deliveryState: delivery,
    text: text,
    reply: reply,
    ownReaction: ownReaction,
    peerReaction: peerReaction,
  );

  group('sanitizeEmojiForA11y', () {
    test('strips C0/C1 and bidi/format controls, keeps the emoji', () {
      // A hostile field: bidi override + a newline + a control, around 👍.
      const hostile = '\u202E\n👍\u200F';
      final clean = sanitizeEmojiForA11y(hostile);
      expect(clean, '👍');
      expect(clean.contains('\u202E'), isFalse);
      expect(clean.contains('\n'), isFalse);
    });

    test('keeps a legitimate ZWJ emoji sequence intact', () {
      const family = '👨‍👩‍👧'; // ZWJ sequence.
      expect(sanitizeEmojiForA11y(family), family);
    });

    test('bounds an over-length (>64 byte) field defensively', () {
      final long = '👍' * 40; // 160 bytes.
      final clean = sanitizeEmojiForA11y(long);
      expect(clean.length, lessThan(long.length));
    });
  });

  testWidgets('sent bubble shows the delivered check + a11y label', (
    tester,
  ) async {
    await tester.pumpWidget(host(MessageBubble(message: msg(outbound: true))));
    await tester.pumpAndSettle();
    expect(find.byType(CheckGlyph), findsOneWidget);
    expect(
      find.bySemanticsLabel(en.chat_deliveryDeliveredA11y),
      findsOneWidget,
    );
  });

  testWidgets('waiting bubble shows the WAITING overline', (tester) async {
    await tester.pumpWidget(
      host(
        MessageBubble(
          message: msg(outbound: true, delivery: DeliveryState.waiting),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(en.chat_waitingHeader), findsOneWidget);
    expect(find.bySemanticsLabel(en.chat_deliveryWaitingA11y), findsOneWidget);
  });

  testWidgets('reaction chip a11y sanitizes a hostile peer emoji', (
    tester,
  ) async {
    // A modified client packs a bidi override around the emoji.
    const hostile = '\u202E👍';
    await tester.pumpWidget(
      host(MessageBubble(message: msg(outbound: true, peerReaction: hostile))),
    );
    await tester.pumpAndSettle();
    // The announcement carries the sanitized emoji, never the control char.
    expect(
      find.bySemanticsLabel(en.chat_reactionPeerA11y('👍')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(en.chat_reactionPeerA11y(hostile)),
      findsNothing,
    );
  });

  testWidgets('own reaction chip carries the tap-to-remove a11y label', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(MessageBubble(message: msg(outbound: false, ownReaction: '❤️'))),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(en.chat_reactionOwnA11y('❤️')),
      findsOneWidget,
    );
  });

  testWidgets('quoted reply shows the referent excerpt', (tester) async {
    await tester.pumpWidget(
      host(
        MessageBubble(
          message: msg(
            outbound: true,
            text: 'a reply',
            reply: ReplyPreview.referent(
              referentRecordId: id(9),
              kind: ReplyReferentKind.text,
              excerpt: 'the original',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('the original'), findsOneWidget);
    expect(find.text('a reply'), findsOneWidget);
  });

  testWidgets('gone referent renders the neutral tombstone', (tester) async {
    await tester.pumpWidget(
      host(
        MessageBubble(
          message: msg(
            outbound: false,
            text: 'orphan',
            reply: const ReplyPreview.tombstone(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(en.chat_replyTombstone), findsOneWidget);
    expect(find.text('orphan'), findsOneWidget);
  });

  testWidgets('actions card shows the six presets + Reply + Delete', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        MessageActionsCard(
          message: msg(outbound: false),
          onReact: (_) {},
          onRemoveReaction: () {},
          onReply: () {},
          onDelete: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final preset in reactionPresets) {
      expect(find.text(preset), findsOneWidget);
    }
    expect(find.text(en.chat_messageActionReply), findsOneWidget);
    expect(find.text(en.chat_messageActionDelete), findsOneWidget);
    expect(find.bySemanticsLabel(en.chat_reactionPickMoreA11y), findsOneWidget);
  });

  testWidgets('tapping a preset reports the chosen emoji', (tester) async {
    String? picked;
    await tester.pumpWidget(
      host(
        MessageActionsCard(
          message: msg(outbound: false),
          onReact: (e) => picked = e,
          onRemoveReaction: () {},
          onReply: () {},
          onDelete: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('❤️'));
    expect(picked, '❤️');
  });

  testWidgets('tapping your current reaction removes it', (tester) async {
    var removed = false;
    await tester.pumpWidget(
      host(
        MessageActionsCard(
          message: msg(outbound: false, ownReaction: '👍'),
          onReact: (_) {},
          onRemoveReaction: () => removed = true,
          onReply: () {},
          onDelete: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('👍').first);
    expect(removed, isTrue);
  });

  testWidgets('composer expiry picker shows string 7 VERBATIM', (tester) async {
    await tester.pumpWidget(host(Composer(onSend: (_, _) {}, onTyping: () {})));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel(en.chat_timerButtonA11y));
    await tester.pumpAndSettle();

    // The honor-system disclaimer, verbatim (never softened).
    expect(find.text(en.chat_expiryDisclaimer), findsOneWidget);
    // The five USER-locked presets.
    expect(find.text(en.chat_timerOff), findsOneWidget);
    expect(find.text(en.chat_timerMinutes(1)), findsOneWidget);
    expect(find.text(en.chat_timerMinutes(15)), findsOneWidget);
    expect(find.text(en.chat_timerHours(1)), findsOneWidget);
    expect(find.text(en.chat_timerHours(24)), findsOneWidget);
  });

  testWidgets('composer send reports text + chosen expiry', (tester) async {
    String? sentText;
    int? sentExpiry;
    await tester.pumpWidget(
      host(
        Composer(
          onSend: (t, e) {
            sentText = t;
            sentExpiry = e;
          },
          onTyping: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Pick 15 min.
    await tester.tap(find.bySemanticsLabel(en.chat_timerButtonA11y));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.chat_timerMinutes(15)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText), 'ping');
    await tester.tap(find.bySemanticsLabel(en.chat_sendA11y));
    await tester.pumpAndSettle();

    expect(sentText, 'ping');
    expect(sentExpiry, 900);
  });

  testWidgets('typing on the composer pings onTyping', (tester) async {
    var typed = false;
    await tester.pumpWidget(
      host(Composer(onSend: (_, _) {}, onTyping: () => typed = true)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'h');
    expect(typed, isTrue);
  });

  testWidgets('typing glyph renders silently (no text)', (tester) async {
    await tester.pumpWidget(host(const PeerTypingBubble()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PeerTypingBubble), findsOneWidget);
    // No text string ever accompanies the glyph (USER 2026-07-07).
    expect(find.byType(Text), findsNothing);
    await tester.pump(const Duration(milliseconds: 1200));
  });

  testWidgets('German-length strings survive the bubble layout', (
    tester,
  ) async {
    // The waiting overline + a long reaction a11y under DE do not overflow.
    await tester.pumpWidget(
      host(
        MessageBubble(
          message: msg(outbound: true, delivery: DeliveryState.waiting),
        ),
        locale: const Locale('de'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
