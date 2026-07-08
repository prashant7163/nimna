import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/app/first_run_store.dart';

/// The F1 first-run gate marker (S16): fresh install ⇒ onboarding shows;
/// markSeen persists; it survives across "relaunches" (a new store over the
/// same dir) and is removed when the store root is wiped (fresh-install
/// symmetry after a panic wipe).
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('nimna-firstrun-'));
  tearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('fresh dir: onboarding not seen', () {
    expect(FirstRunStore(dir).hasSeenOnboarding(), isFalse);
  });

  test(
    'markSeen persists and survives a fresh store over the same dir',
    () async {
      await FirstRunStore(dir).markSeen();
      // A NEW store instance (a relaunch) reads the same marker.
      expect(FirstRunStore(dir).hasSeenOnboarding(), isTrue);
    },
  );

  test('markSeen creates the dir if it does not yet exist', () async {
    final missing = Directory('${dir.path}/nested/store');
    expect(missing.existsSync(), isFalse);
    await FirstRunStore(missing).markSeen();
    expect(FirstRunStore(missing).hasSeenOnboarding(), isTrue);
  });

  test(
    'wiping the store root removes the marker (fresh-install symmetry)',
    () async {
      final store = FirstRunStore(dir);
      await store.markSeen();
      expect(store.hasSeenOnboarding(), isTrue);
      dir.deleteSync(recursive: true);
      expect(store.hasSeenOnboarding(), isFalse);
    },
  );
}
