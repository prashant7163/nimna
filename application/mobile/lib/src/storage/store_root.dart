import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The single on-disk home of everything Nimna persists
/// (app-architecture.md §4): `<ApplicationSupport>/nimna-store/`.
///
/// Never sqflite's default path, never Documents (Files-app-visible), never
/// Caches/tmp (purgeable). One root = one iOS backup-exclusion point + one
/// wipe point. Contents: `nimna.db` (+ WAL/SHM sidecars), `media/`, `diag/`.
class StoreRoot {
  StoreRoot.at(this.root);

  /// Production resolution via path_provider.
  static Future<StoreRoot> resolve() async {
    final support = await getApplicationSupportDirectory();
    return StoreRoot.at(Directory(p.join(support.path, 'nimna-store')));
  }

  final Directory root;

  String get dbPath => p.join(root.path, 'nimna.db');

  File get dbFile => File(dbPath);

  /// SQLite sidecars — deleted with the DB on wipe/reset.
  List<File> get dbSidecars => [
    File('$dbPath-wal'),
    File('$dbPath-shm'),
    File('$dbPath-journal'),
  ];

  Directory get mediaDir => Directory(p.join(root.path, 'media'));

  Directory get diagDir => Directory(p.join(root.path, 'diag'));

  /// Creates the root and its subdirectories (idempotent).
  void create() {
    root.createSync(recursive: true);
    mediaDir.createSync(recursive: true);
    diagDir.createSync(recursive: true);
  }

  /// Deletes everything under the root and recreates it empty — the
  /// deletion half of both destructive reset and full panic wipe (key
  /// destruction, not deletion completeness, is the security boundary).
  void wipeAndRecreate() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
    create();
  }
}
