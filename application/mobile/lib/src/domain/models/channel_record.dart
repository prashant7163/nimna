import 'dart:convert';
import 'dart:typed_data';

/// The plaintext content of one channel record — lives ONLY inside the
/// channel row's ciphertext (spec §6, app-architecture.md §4):
/// own static keypair, peer static pubkey, CRID, label, per-channel
/// settings (push opt-in, default expiry, peer device-token §3.2.1), CDK,
/// created_at, and the per-channel message ordering counter.
///
/// The CDK (channel data key) is the only copy anywhere: message and media
/// ciphertext keys derive from it, so deleting this record cryptographically
/// kills the channel's history (per-channel wipe, app-architecture.md §3).
class ChannelRecord {
  const ChannelRecord({
    required this.id,
    required this.ownStaticPrivate,
    required this.ownStaticPublic,
    required this.peerStaticPublic,
    required this.crid,
    required this.label,
    required this.cdk,
    required this.createdAtMs,
    this.pushOptIn = false,
    this.readReceiptsOptIn = false,
    this.typingEnabled = true,
    this.defaultExpirySeconds,
    this.peerDeviceToken,
    this.nextSeq = 0,
    this.sort = 0,
  });

  /// Random local surrogate id (16 bytes) — the only plaintext identifier.
  final Uint8List id;

  final Uint8List ownStaticPrivate;
  final Uint8List ownStaticPublic;
  final Uint8List peerStaticPublic;
  final Uint8List crid;
  final String label;

  /// Channel data key (32 random bytes, minted at channel creation).
  final Uint8List cdk;

  final int createdAtMs;

  /// Per-channel push toggle — DEFAULT OFF (spec §3.2.1).
  final bool pushOptIn;

  /// Per-channel read-receipts opt-in — DEFAULT OFF (spec §5; USER
  /// 2026-07-07). When on, this device sends CONTROL 0x02 read receipts for
  /// peer messages it reads; the peer then sees "Seen". Off = the peer never
  /// learns what was read on this line. Local-only preference (spec §6).
  final bool readReceiptsOptIn;

  /// Per-channel typing-indicator toggle — DEFAULT ON (USER 2026-07-07). When
  /// off, this device sends no CONTROL 0x01 typing heartbeats for this line
  /// (the F7 discretion mitigation for the keystroke-timing leak). Local-only.
  final bool typingEnabled;

  final int? defaultExpirySeconds;

  /// Peer device token — stored only here (encrypted), never sent anywhere
  /// but inside E2E payloads (spec §3.2.1).
  final Uint8List? peerDeviceToken;

  /// Per-channel monotonic message ordering counter — local, never
  /// wall-clock (app-architecture.md §4).
  final int nextSeq;

  /// Plaintext ordering column value for the channel list.
  final int sort;

  ChannelRecord copyWith({
    String? label,
    bool? pushOptIn,
    bool? readReceiptsOptIn,
    bool? typingEnabled,
    int? Function()? defaultExpirySeconds,
    Uint8List? Function()? peerDeviceToken,
    int? nextSeq,
    int? sort,
  }) => ChannelRecord(
    id: id,
    ownStaticPrivate: ownStaticPrivate,
    ownStaticPublic: ownStaticPublic,
    peerStaticPublic: peerStaticPublic,
    crid: crid,
    label: label ?? this.label,
    cdk: cdk,
    createdAtMs: createdAtMs,
    pushOptIn: pushOptIn ?? this.pushOptIn,
    readReceiptsOptIn: readReceiptsOptIn ?? this.readReceiptsOptIn,
    typingEnabled: typingEnabled ?? this.typingEnabled,
    defaultExpirySeconds: defaultExpirySeconds != null
        ? defaultExpirySeconds()
        : this.defaultExpirySeconds,
    peerDeviceToken: peerDeviceToken != null
        ? peerDeviceToken()
        : this.peerDeviceToken,
    nextSeq: nextSeq ?? this.nextSeq,
    sort: sort ?? this.sort,
  );

  Uint8List toBytes() => utf8.encode(
    json.encode({
      'v': 1,
      'ownPriv': base64.encode(ownStaticPrivate),
      'ownPub': base64.encode(ownStaticPublic),
      'peerPub': base64.encode(peerStaticPublic),
      'crid': base64.encode(crid),
      'label': label,
      'cdk': base64.encode(cdk),
      'createdAtMs': createdAtMs,
      'pushOptIn': pushOptIn,
      // Serialized only when non-default so older records (which lack the key)
      // decode to the correct defaults: read receipts OFF, typing ON.
      if (readReceiptsOptIn) 'readReceipts': readReceiptsOptIn,
      if (!typingEnabled) 'typingOff': true,
      if (defaultExpirySeconds != null) 'expiryS': defaultExpirySeconds,
      if (peerDeviceToken != null) 'peerToken': base64.encode(peerDeviceToken!),
      'nextSeq': nextSeq,
    }),
  );

  static ChannelRecord fromBytes(Uint8List id, int sort, Uint8List bytes) {
    final map = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    return ChannelRecord(
      id: id,
      ownStaticPrivate: base64.decode(map['ownPriv'] as String),
      ownStaticPublic: base64.decode(map['ownPub'] as String),
      peerStaticPublic: base64.decode(map['peerPub'] as String),
      crid: base64.decode(map['crid'] as String),
      label: map['label'] as String,
      cdk: base64.decode(map['cdk'] as String),
      createdAtMs: map['createdAtMs'] as int,
      pushOptIn: map['pushOptIn'] as bool,
      // Backward-compatible: absent key ⇒ default (receipts OFF, typing ON).
      readReceiptsOptIn: map['readReceipts'] as bool? ?? false,
      typingEnabled: !(map['typingOff'] as bool? ?? false),
      defaultExpirySeconds: map['expiryS'] as int?,
      peerDeviceToken: map.containsKey('peerToken')
          ? base64.decode(map['peerToken'] as String)
          : null,
      nextSeq: map['nextSeq'] as int,
      sort: sort,
    );
  }
}
