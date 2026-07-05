import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nimna/l10n/app_localizations_en.dart';
import 'package:nimna/src/app/app.dart';
import 'package:nimna/src/app/bootstrap.dart';
import 'package:nimna/src/domain/models/channel_record.dart';
import 'package:nimna/src/domain/models/message_record.dart';
import 'package:nimna/src/storage/backup/backup_exclusion.dart';
import 'package:nimna/src/storage/store_root.dart';

/// Device-attached slice of the S7 done-check (run on the Android emulator
/// and iOS simulator; §7.3's isExcludedFromBackup read-back also on a real
/// iPhone):
///
///   `flutter test integration_test/app_boot_test.dart -d <device-id>`
///
/// Covers: real keystore + real store root, encrypted persistence across a
/// storage seal/reopen cycle, iOS backup-exclusion attribute + re-assert
/// path, and the app booting to the canonical empty shell.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boots, persists encrypted records, backup-excluded', (
    tester,
  ) async {
    final services = await bootstrapNimna();
    final storage = services.storage;
    final cipher = storage.cipher;

    // --- storage round trip on the real device stack ------------------
    const label = 'INTEG_MARKER_LABEL';
    const body = 'INTEG_MARKER_BODY';
    final existing = storage.channels.all
        .where((c) => c.label == label)
        .toList();
    for (final c in existing) {
      await storage.wipeChannel(c.id); // idempotent re-runs
    }

    final channel = ChannelRecord(
      id: cipher.newRecordId(),
      ownStaticPrivate: cipher.randomBytes(32),
      ownStaticPublic: cipher.randomBytes(32),
      peerStaticPublic: cipher.randomBytes(32),
      crid: cipher.randomBytes(16),
      label: label,
      cdk: cipher.randomBytes(32),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await storage.channels.create(channel);
    await storage.messages.append(
      channel.id,
      MessageRecord(
        id: cipher.newRecordId(),
        direction: MessageDirection.sent,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        type: MessageType.text,
        text: body,
      ),
    );

    // Seal + reopen = the on-device restart seam.
    await storage.seal();
    await storage.open();

    final restored = storage.channels.all.where((c) => c.label == label);
    expect(restored, hasLength(1));
    final messages = await storage.messages.byChannel(channel.id);
    expect(messages.map((m) => m.text), contains(body));

    // Raw DB bytes on device must not contain the plaintext markers.
    final root = await StoreRoot.resolve();
    final dbBytes = root.dbFile.readAsBytesSync();
    expect(String.fromCharCodes(dbBytes).contains(label), isFalse);
    expect(String.fromCharCodes(dbBytes).contains(body), isFalse);

    // --- iOS backup exclusion + re-assert path (§7.3) ------------------
    if (Platform.isIOS) {
      final exclusion = BackupExclusion(diag: services.diag);
      expect(
        await exclusion.isExcluded(root.root.path),
        isTrue,
        reason: 'store root must be excluded from backup after boot',
      );
      // Clear the attribute, prove it is really cleared, then prove the
      // launch-path assert re-sets it.
      await exclusion.debugClearExcluded(root.root.path);
      expect(await exclusion.isExcluded(root.root.path), isFalse);
      await exclusion.assertExcluded(root.root.path);
      expect(await exclusion.isExcluded(root.root.path), isTrue);
    }

    // --- the app boots to the canonical shell --------------------------
    await tester.pumpWidget(NimnaApp(services: services));
    await tester.pumpAndSettle();
    final en = AppLocalizationsEn();
    // Channel exists, but S7's shell is the static empty-state scaffold.
    expect(find.text(en.channelListEmptyHeadline), findsOneWidget);

    // Cleanup so re-runs stay deterministic.
    await storage.wipeChannel(channel.id);
  });
}
