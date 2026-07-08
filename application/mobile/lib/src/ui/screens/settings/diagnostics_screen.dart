import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/app_scope.dart';
import '../../../diag/diag_export.dart';
import '../../../diag/diag_record.dart';
import '../../theme/nimna_tokens.dart';
import '../../widgets/nav_bar.dart';

/// The diagnostics export screen (F8 settings; architect Concern 2). Explains
/// what the local log is — event codes and times only, never content — and
/// that nothing auto-uploads, then offers a single deliberate "Share the log"
/// through the OS share sheet (no network from the app).
///
/// Reachable ONLY behind an OPEN lock gate (settings lives inside the app-lock
/// perimeter). `Diag.readAll()` throws when the perimeter is sealed; this
/// screen handles that gracefully (empty state), never a crash. Every string is
/// ARB-sourced; the rendered dump is structurally content-free.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  List<DiagRecord> _records = const [];
  bool _read = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_read) {
      return;
    }
    _read = true;
    try {
      _records = AppScope.of(context).diag.readAll();
    } on StateError {
      // Sealed perimeter (should not happen behind an open lock gate): show the
      // empty state rather than surface a crash.
      _records = const [];
    }
  }

  void _share() {
    if (_records.isEmpty) {
      return;
    }
    // The rendered dump is structurally content-free (enum names + ints only).
    // Handed to the OS share sheet IN-MEMORY via ShareParams(text:) — no temp
    // file, so no transient plaintext-at-rest; nothing auto-uploads (a single
    // deliberate user tap). Third sanctioned share_plus call site (fenced).
    unawaited(
      SharePlus.instance.share(ShareParams(text: DiagExport.render(_records))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;
    final empty = _records.isEmpty;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NimnaNavBar(title: l10n.diag_shareTitle),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NimnaSpacing.screenMargin,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: NimnaSpacing.base * 2),
                    Text(
                      l10n.diag_shareExplainer,
                      style: text.bodyMedium?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    if (empty)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: NimnaSpacing.base * 4,
                        ),
                        child: Text(
                          l10n.diag_shareEmpty,
                          textAlign: TextAlign.center,
                          style: text.bodySmall?.copyWith(
                            color: tokens.textTertiary,
                          ),
                        ),
                      ),
                    FilledButton(
                      onPressed: empty ? null : _share,
                      child: Text(l10n.diag_shareAction),
                    ),
                    const SizedBox(height: NimnaSpacing.base * 6),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
