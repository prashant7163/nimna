import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app/app_scope.dart';
import '../../app/routes.dart';
import '../../domain/models/channel_record.dart';
import '../../pairing/initiator/create_line_entry.dart';
import '../../pairing/joiner/join_line_entry.dart';
import '../../session/chat/line_presence.dart';
import '../theme/nimna_tokens.dart';
import '../widgets/glyphs.dart';

/// The channel-list scaffold (wireframe F4). Empty (F4.4) it renders voice-guide
/// string 4 VERBATIM; populated (design 04) it lists the stored lines, each row
/// a label + status subtitle that taps into the line (S16: opening a line is
/// the presence trigger — [LinePresence] connects LISTENING and offers Knock).
///
/// Row status is per-open-line scope: the list holds no live connection, so
/// every row reads "Quiet" (channelListStatusQuiet) until opened. The design's
/// live "On the line" / "Waiting: N" row statuses presuppose list-level
/// presence memory — out of S16 scope, flagged for S18.
///
/// From S8, "Create a code" is live — it enters the F2 initiator flow through
/// [startCreateLine], the G2 single entry point (S17 gates exactly that
/// function). On first frame the screen also adopts a pending pairing surviving
/// from a previous run (read at boot; F2.4 edge: the wait resumes inside the
/// TTL, F2.8 if it lapsed while away).
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

  // The G2 single entry point (S17 gates exactly `startCreateLine`) — routed
  // through ONE call site here so the empty and populated F4 bodies share it.
  void _onCreate() => unawaited(startCreateLine(context));
  void _onJoin() => unawaited(startJoinLine(context));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;
    // The channel list renders inside the open LockGate perimeter; a transient
    // build under a sealed store (mid-seal relayout) reads as empty rather than
    // throwing — the getter itself asserts an open store.
    final storage = AppScope.of(context).storage;
    final records = storage.isOpen && storage.channels.isOpen
        ? storage.channels.all
        : const <ChannelRecord>[];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NimnaSpacing.screenMargin,
          ),
          child: records.isEmpty
              ? _emptyBody(l10n, tokens, text)
              : _populatedBody(records, l10n, tokens, text),
        ),
      ),
    );
  }

  /// F4.4 — the empty channel list (voice-guide string 4, verbatim).
  Widget _emptyBody(AppLocalizations l10n, NimnaTokens tokens, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titleBar(l10n, text),
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
        FilledButton(onPressed: _onCreate, child: Text(l10n.actionCreateCode)),
        const SizedBox(height: NimnaSpacing.base * 2),
        OutlinedButton(onPressed: _onJoin, child: Text(l10n.actionEnterCode)),
        const Spacer(flex: 3),
        _settingsFooter(l10n, tokens, text),
      ],
    );
  }

  /// Design 04 — the populated line list. Each row opens the line (the presence
  /// trigger). The Create / Enter actions stay reachable below the list.
  Widget _populatedBody(
    List<ChannelRecord> records,
    AppLocalizations l10n,
    NimnaTokens tokens,
    TextTheme text,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titleBar(l10n, text),
        Expanded(
          child: ListView(
            children: [
              for (final record in records)
                _channelRow(record, l10n, tokens, text),
            ],
          ),
        ),
        FilledButton(onPressed: _onCreate, child: Text(l10n.actionCreateCode)),
        const SizedBox(height: NimnaSpacing.base * 2),
        OutlinedButton(onPressed: _onJoin, child: Text(l10n.actionEnterCode)),
        const SizedBox(height: NimnaSpacing.base * 2),
        _settingsFooter(l10n, tokens, text),
      ],
    );
  }

  Widget _titleBar(AppLocalizations l10n, TextTheme text) {
    return SizedBox(
      height: NimnaSpacing.listRowSettings,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(l10n.appTitle, style: text.titleMedium),
      ),
    );
  }

  Widget _channelRow(
    ChannelRecord record,
    AppLocalizations l10n,
    NimnaTokens tokens,
    TextTheme text,
  ) {
    return Semantics(
      button: true,
      label: record.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pushNamed(
          Routes.line,
          arguments: LinePresenceArgs(
            channelId: record.id,
            label: record.label,
          ),
        ),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: NimnaSpacing.listRowSettings,
          ),
          padding: const EdgeInsets.symmetric(vertical: NimnaSpacing.base),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      record.label,
                      style: text.bodyMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.channelListStatusQuiet,
                      style: text.bodySmall?.copyWith(
                        color: tokens.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              // The idle mini line indicator (design 04 `.minil .line idle`).
              Container(
                width: 24,
                height: NimnaLine.thickness,
                color: tokens.lineIdle,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// F4 list footer (wireframe F4.4): the Settings entry row.
  Widget _settingsFooter(
    AppLocalizations l10n,
    NimnaTokens tokens,
    TextTheme text,
  ) {
    return Semantics(
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
                  style: text.bodySmall?.copyWith(color: tokens.textSecondary),
                ),
              ),
              ChevronGlyph(color: tokens.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
