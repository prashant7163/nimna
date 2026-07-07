import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/nimna_tokens.dart';

/// The design system's toast (components.md): bottom, above safe-area, bg
/// `surface3`, radius 10, `body` type, max 2 lines, auto-dismiss 3 s, one
/// at a time, no icons, no colors. A custom overlay, NOT SnackBar —
/// Material styling fights the design (flutter-notes).
void showNimnaToast(BuildContext context, String message) {
  _ToastHost.show(Overlay.of(context), message);
}

class _ToastHost {
  static OverlayEntry? _current;
  static Timer? _timer;

  static void show(OverlayState overlay, String message) {
    _timer?.cancel();
    _current?.remove();
    final entry = OverlayEntry(
      builder: (context) => _ToastSurface(message: message),
    );
    _current = entry;
    overlay.insert(entry);
    _timer = Timer(const Duration(seconds: 3), () {
      _current?.remove();
      _current = null;
    });
  }
}

class _ToastSurface extends StatelessWidget {
  const _ToastSurface({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    return Positioned(
      left: NimnaSpacing.screenMargin,
      right: NimnaSpacing.screenMargin,
      bottom: MediaQuery.paddingOf(context).bottom + NimnaSpacing.screenMargin,
      child: IgnorePointer(
        child: Material(
          color: tokens.surface3,
          borderRadius: BorderRadius.circular(NimnaRadius.small),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NimnaSpacing.base * 4,
              vertical: NimnaSpacing.base * 3,
            ),
            child: Text(
              message,
              style: NimnaText.body.copyWith(color: tokens.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
