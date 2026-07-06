import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app/routes.dart';
import '../theme/nimna_tokens.dart';
import '../widgets/glyphs.dart';

/// S7 placeholder shell: the channel-list scaffold in its empty state
/// (wireframe F4.4), rendering voice-guide string 4 VERBATIM from the EN
/// ARB. Its two actions are present but disabled stubs — Create a code is
/// the S8/S12 flow, Enter a code is S9. Real screens implement `designs/`
/// verbatim from S8 on; nothing here is invented copy.
class ChannelListScreen extends StatelessWidget {
  const ChannelListScreen({super.key});

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
                onPressed: null, // S8/S12 flow — stub in S7.
                child: Text(l10n.actionCreateCode),
              ),
              const SizedBox(height: NimnaSpacing.base * 2),
              OutlinedButton(
                onPressed: null, // S9 flow — stub in S7.
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
