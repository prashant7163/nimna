import 'dart:io';

import 'package:flutter/services.dart';

import '../../diag/diag.dart';
import '../../diag/diag_events.dart';

/// iOS cloud-backup exclusion (app-architecture.md §7).
///
/// `isExcludedFromBackup = true` is set on the store root at creation and
/// re-asserted every launch — the attribute is filesystem metadata that
/// restores/migrations can drop. Implemented over the hand-written
/// `app.nimna/storage` platform channel (ios/Runner/AppDelegate.swift);
/// no dependency exists for a URL-resource-value write.
///
/// Android needs no runtime call: `allowBackup="false"` +
/// `dataExtractionRules` in the manifest exclude everything from both
/// cloud-backup and device-transfer.
class BackupExclusion {
  BackupExclusion({required this._diag, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.nimna/storage');

  final Diag _diag;
  final MethodChannel _channel;

  /// Sets and read-back-verifies the exclusion attribute on [path].
  /// Outcome lands in the diagnostic log (events only).
  Future<bool> assertExcluded(String path) async {
    if (!Platform.isIOS) {
      return true;
    }
    try {
      await _channel.invokeMethod<bool>('setExcludedFromBackup', {
        'path': path,
      });
      final verified = await _channel.invokeMethod<bool>(
        'isExcludedFromBackup',
        {'path': path},
      );
      if (verified ?? false) {
        _diag.log(DiagEvent.backupExclusionAsserted);
        return true;
      }
      _diag.log(
        DiagEvent.backupExclusionFailed,
        code: DiagCode.platformChannelUnavailable,
      );
      return false;
    } on PlatformException {
      _diag.log(DiagEvent.backupExclusionFailed, code: DiagCode.ioError);
      return false;
    } on MissingPluginException {
      _diag.log(
        DiagEvent.backupExclusionFailed,
        code: DiagCode.platformChannelUnavailable,
      );
      return false;
    }
  }

  /// TEST SEAM (integration re-assert proof, app-architecture.md §7.3):
  /// clears the attribute so the next launch can prove it re-asserts.
  Future<bool> debugClearExcluded(String path) async {
    if (!Platform.isIOS) {
      return true;
    }
    final cleared = await _channel.invokeMethod<bool>(
      'clearExcludedFromBackup',
      {'path': path},
    );
    return cleared ?? false;
  }

  /// Reads the current attribute value (integration-test probe).
  Future<bool> isExcluded(String path) async {
    if (!Platform.isIOS) {
      return true;
    }
    final value = await _channel.invokeMethod<bool>('isExcludedFromBackup', {
      'path': path,
    });
    return value ?? false;
  }
}
