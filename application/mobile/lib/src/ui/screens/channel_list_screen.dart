import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app/routes.dart';
import '../../pairing/initiator/create_line_entry.dart';
import '../theme/nimna_tokens.dart';
import '../widgets/glyphs.dart';

/// The channel-list scaffold in its empty state (wireframe F4.4),
/// rendering voice-guide string 4 VERBATIM from the EN ARB. From S8,
/// "Create a code" is live — it enters the F2 initiator flow through
/// [startCreateLine], the G2 single entry point (S17 gates exactly that
/// function). "Enter a code" remains an S9 stub. On first frame the
/// screen also adopts a pending pairing surviving from a previous run
/// (read at boot; F2.4 edge: the wait resumes inside the TTL, F2.8 if it
/// lapsed while away).
class ChannelListScreen extends StatefulWidget {
  const ChannelListScreen({super.key});

  @override
  State<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends State<ChannelListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(resumeCreateLineIfPending(context));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NimnaSpacing.screenMargin,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: NimnaSpacing.listRowSettings,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(l10n.appTitle, style: text.titleMedium),
                ),
              ),
              const Spacer(flex: 2),
              Text(
                l10n.channelListEmptyHeadline,
                style: text.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: NimnaSpacing.base * 2),
              Text(
                l10n.channelListEmptyBody,
                style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: NimnaSpacing.base * 6),
              FilledButton(
                onPressed: () => unawaited(startCreateLine(context)),
                child: Text(l10n.actionCreateCode),
              ),
              const SizedBox(height: NimnaSpacing.base * 2),
              OutlinedButton(
                onPressed: null, // S9 flow — stub until then.
                child: Text(l10n.actionEnterCode),
              ),
              const Spacer(flex: 3),
              // F4 list footer (wireframe F4.4): the Settings entry row.
              Semantics(
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pushNamed(Routes.settings),
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: NimnaSpacing.listRowSettings,
                    ),
                    alignment: AlignmentDirectional.centerStart,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.settings_title,
                            style: text.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                            ),
                          ),
                        ),
                        ChevronGlyph(color: tokens.textTertiary),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
