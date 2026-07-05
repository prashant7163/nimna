import 'dart:convert';
import 'dart:typed_data';

/// The plaintext content of one media-index record — lives ONLY inside the
/// media_ix row's ciphertext (app-architecture.md §4): manifest message
/// linkage, mime, byte length, content hash, blob file id.
class MediaIndexRecord {
  const MediaIndexRecord({
    required this.id,
    required this.mime,
    required this.byteLength,
    required this.contentHash,
    this.msgId,
  });

  /// Random local surrogate id (16 bytes) — also the blob file id
  /// (`<root>/media/<hex(id)>`).
  final Uint8List id;

  /// Manifest message linkage (protocol msg_id; S9+ fills for real traffic).
  final Uint8List? msgId;

  final String mime;
  final int byteLength;

  /// SHA-256 of the plaintext content.
  final Uint8List contentHash;

  Uint8List toBytes() => utf8.encode(
    json.encode({
      'v': 1,
      if (msgId != null) 'msgId': base64.encode(msgId!),
      'mime': mime,
      'len': byteLength,
      'hash': base64.encode(contentHash),
      'blob': base64.encode(id),
    }),
  );

  static MediaIndexRecord fromBytes(Uint8List id, Uint8List bytes) {
    final map = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    return MediaIndexRecord(
      id: id,
      msgId: map.containsKey('msgId')
          ? base64.decode(map['msgId'] as String)
          : null,
      mime: map['mime'] as String,
      byteLength: map['len'] as int,
      contentHash: base64.decode(map['hash'] as String),
    );
  }
}
