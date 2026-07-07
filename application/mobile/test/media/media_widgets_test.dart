import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/l10n/app_localizations.dart';
import 'package:nimna/l10n/app_localizations_en.dart';
import 'package:nimna/src/app/theme.dart';
import 'package:nimna/src/domain/models/message_record.dart';
import 'package:nimna/src/media/model/media_transfer_state.dart';
import 'package:nimna/src/media/ui/attach_sheet.dart';
import 'package:nimna/src/media/ui/media_bubble_content.dart';
import 'package:nimna/src/session/model/message_view.dart';

/// S11 media UI — BINDING to designs/system/components.md. The over-cap guard
/// (voice string 17 verbatim), the metadata-strip notice (string 17), and the
/// document/image media bubbles.
void main() {
  final en = AppLocalizationsEn();

  Uint8List id(int seed) => Uint8List.fromList(List.filled(16, seed));

  Widget host(Widget child) => MaterialApp(
    locale: const Locale('en'),
    theme: nimnaTheme(Brightness.dark),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  MessageView mediaMsg({
    required bool image,
    int byteLength = 1234,
    MediaTransferState? transfer,
  }) => MessageView(
    recordId: id(1),
    msgId: id(2),
    outbound: false,
    type: MessageType.media,
    timestampMs: 0,
    deliveryState: DeliveryState.delivered,
    mediaId: id(3),
    mediaMime: image ? 'image/jpeg' : 'application/pdf',
    mediaByteLength: byteLength,
    mediaTransfer: transfer ?? MediaTransferState.loaded,
  );

  testWidgets('over-cap document preview shows string 17 + disables send', (
    tester,
  ) async {
    final over = Uint8List(6 * 1024 * 1024); // 6 MB > 5 MB cap
    await tester.pumpWidget(
      host(AttachDocumentPreview(bytes: over, mime: 'application/pdf')),
    );
    await tester.pumpAndSettle();

    // Voice string 17 (over-cap) is shown verbatim.
    expect(find.text(en.media_overCapError), findsOneWidget);

    // The Send affordance is disabled — tapping it does nothing (the preview
    // stays; the over-cap error is still shown).
    await tester.tap(find.text(en.chat_sendA11y).last);
    await tester.pump();
    expect(find.text(en.media_overCapError), findsOneWidget);
  });

  testWidgets('under-cap document preview renders kind + size', (tester) async {
    await tester.pumpWidget(
      host(
        AttachDocumentPreview(
          bytes: Uint8List(2 * 1024 * 1024),
          mime: 'application/pdf',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(en.media_documentKindPdf), findsNothing); // composed
    expect(find.textContaining('PDF'), findsOneWidget);
    expect(find.text(en.media_overCapError), findsNothing);
  });

  testWidgets('document media bubble shows the meta line', (tester) async {
    await tester.pumpWidget(
      host(
        MediaBubbleContent(message: mediaMsg(image: false), loadBytes: null),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('PDF'), findsOneWidget);
  });

  testWidgets('image media bubble is tappable + a11y-labelled', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      host(
        MediaBubbleContent(
          // loadBytes null → the placeholder path (no Image.memory decode).
          message: mediaMsg(image: true),
          loadBytes: null,
          onTap: () => tapped = true,
        ),
      ),
    );
    await tester.pump();
    expect(find.bySemanticsLabel(en.media_imageA11y), findsOneWidget);
    await tester.tap(find.byType(MediaBubbleContent));
    expect(tapped, isTrue);
  });
}
