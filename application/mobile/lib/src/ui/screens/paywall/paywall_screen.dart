import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/app_scope.dart';
import '../../../billing/entitlement_source.dart';
import '../../theme/nimna_tokens.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/nimna_symbol.dart';
import '../../widgets/nimna_toast.dart';

// Platform store brand names — non-translated proper nouns, resolved into the
// {store} slot of the auto-renew disclosure (USER-approved 2026-07-07 12:39).
const String _kAppStore = 'App Store';
const String _kGooglePlay = 'Google Play';

/// What the paywall hands back to the creation gate
/// (`create_line_entry.dart`). Anything other than [dismissed] means the
/// subscription is now active and creation may proceed; the two success
/// variants only differ in which toast the caller shows (F9.4 vs F9.5).
enum PaywallResult { dismissed, purchased, restored }

/// F9 · Paywall — the calm full-screen creation gate (hi-fi screen 09 +
/// `.light` / wireframe F9; USER decision: calm full-screen, never a nag).
///
/// It is reached ONLY from `startCreateLine` when the store's signed
/// on-device cache does not confirm an active creation subscription — never
/// from joining, never on launch, never on a timer (spec §10). The receiver
/// never sees this screen.
///
/// The permanence guarantee rides at feature prominence, never fine print.
/// No number is ever hardcoded: the CTA renders `ProductDetails.price` from
/// the store (spec §10 numberless lock). The store-mandated auto-renew
/// disclosure (USER-approved 2026-07-07 12:39; `{store}` resolves to the
/// platform store brand) + Terms/Privacy links sit beside the CTA, in the
/// PM-confirmed order: honesty line → disclosure → Terms · Privacy.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  /// null while the first entitlement query is in flight.
  EntitlementStatus? _status;

  /// The store's localized price string — the only price that ever exists
  /// (spec §10). null unless the buy state is ready to render.
  String? _price;

  /// A store call is in flight (buy or restore) — buttons disable, and
  /// restore shows its "Checking with the store…" line.
  bool _busy = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    // Query after the first frame: AppScope depends on inherited widgets and
    // the loading skeleton renders meanwhile (no setState during initState).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _query();
      }
    });
  }

  /// Re-enters the loading state and re-queries (the "Try again" affordance).
  void _retry() {
    setState(() {
      _status = null;
      _price = null;
    });
    _query();
  }

  /// Reads the platform entitlement cache and, when inactive, the store
  /// price. Fail-closed: an unresolved query or a missing price renders the
  /// calm reconnect state rather than a priceless CTA.
  Future<void> _query() async {
    final billing = AppScope.of(context).billing;
    final status = await billing.entitlementStatus();
    if (!mounted) {
      return;
    }
    if (status == EntitlementStatus.active) {
      // Race: became entitled between the gate and here — proceed to create.
      Navigator.of(context).pop(PaywallResult.restored);
      return;
    }
    String? price;
    if (status == EntitlementStatus.inactive) {
      price = await billing.localizedPrice();
      if (!mounted) {
        return;
      }
    }
    setState(() {
      // No price ⇒ we cannot honour the numberless CTA; show reconnect.
      _status = (status == EntitlementStatus.inactive && price == null)
          ? EntitlementStatus.unresolved
          : status;
      _price = price;
    });
  }

  Future<void> _buy() async {
    final l10n = AppLocalizations.of(context)!;
    final billing = AppScope.of(context).billing;
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    final outcome = await billing.purchaseCreationSubscription();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    switch (outcome) {
      case PurchaseOutcome.purchased:
        navigator.pop(PaywallResult.purchased);
      case PurchaseOutcome.storeUnreachable:
        showNimnaToast(context, l10n.billing_storeUnreachable);
      case PurchaseOutcome.cancelled:
      case PurchaseOutcome.failed:
      case PurchaseOutcome.pending:
        // F9.6: calm return — the page holds still, no error banner, no
        // "are you sure?". The store owns any real-failure dialog.
        break;
    }
  }

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context)!;
    final billing = AppScope.of(context).billing;
    final navigator = Navigator.of(context);
    setState(() => _restoring = true);
    final outcome = await billing.restore();
    if (!mounted) {
      return;
    }
    setState(() => _restoring = false);
    switch (outcome) {
      case RestoreOutcome.restored:
        navigator.pop(PaywallResult.restored);
      case RestoreOutcome.nothingFound:
        showNimnaToast(context, l10n.billing_restoreNothing);
      case RestoreOutcome.storeUnreachable:
        showNimnaToast(context, l10n.billing_storeUnreachable);
    }
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
              // Navbar: dismiss ✕, trailing (F9.2 / screen 09). Nothing
              // follows the user afterward — no badge, no reminder.
              SizedBox(
                height: 52,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Semantics(
                    button: true,
                    label: MaterialLocalizations.of(context).closeButtonTooltip,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          Navigator.of(context).pop(PaywallResult.dismissed),
                      child: SizedBox.square(
                        dimension: NimnaSpacing.touchTargetMin,
                        child: Center(
                          child: CloseGlyph(color: tokens.textSecondary),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 48),
                      NimnaSymbol(tokens: tokens),
                      const SizedBox(height: 36),
                      Text(l10n.billing_headline, style: text.displaySmall),
                      const SizedBox(height: 12),
                      Text(
                        l10n.billing_subhead,
                        style: text.bodyLarge?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 36),
                      _FeaturePoint(
                        title: l10n.billing_pointSubscriptionTitle,
                        caption: l10n.billing_pointSubscriptionCaption,
                      ),
                      const SizedBox(height: 18),
                      _FeaturePoint(
                        title: l10n.billing_pointPermanenceTitle,
                        caption: l10n.billing_pointPermanenceCaption,
                      ),
                      const SizedBox(height: 18),
                      _FeaturePoint(
                        title: l10n.billing_pointNoAccountTitle,
                        caption: l10n.billing_pointNoAccountCaption,
                      ),
                      const SizedBox(height: 18),
                      _FeaturePoint(
                        title: l10n.billing_pointJoiningFreeTitle,
                        caption: l10n.billing_pointJoiningFreeCaption,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              _buildBottom(context, l10n, tokens, text),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottom(
    BuildContext context,
    AppLocalizations l10n,
    NimnaTokens tokens,
    TextTheme text,
  ) {
    final isBuy = _status == EntitlementStatus.inactive && _price != null;
    final children = <Widget>[];

    if (isBuy) {
      // Buy state (F9.2): CTA then the ghost Restore (screen 09 order).
      children.add(
        FilledButton(
          onPressed: _busy ? null : _buy,
          child: Text(l10n.billing_ctaStart(_price!)),
        ),
      );
      children.add(const SizedBox(height: 8));
      children.add(_restoreButton(l10n, tokens));
    } else if (_status == null) {
      // Brief loading — reserve the CTA height quietly, no spinner (no
      // urgency mechanics, spec §10).
      children.add(const SizedBox(height: 52));
    } else {
      // Reconnect state (fail-closed, offline/unresolved — CODE decision).
      children.add(
        Text(
          l10n.billing_reconnectToVerify,
          style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
          textAlign: TextAlign.center,
        ),
      );
      children.add(const SizedBox(height: 12));
      children.add(
        FilledButton(
          onPressed: (_busy || _restoring) ? null : _retry,
          child: Text(l10n.billing_tryAgain),
        ),
      );
      children.add(const SizedBox(height: 8));
      children.add(_restoreButton(l10n, tokens));
    }

    if (_restoring) {
      children.add(const SizedBox(height: 8));
      children.add(
        Text(
          l10n.billing_restoreChecking,
          style: text.bodySmall?.copyWith(color: tokens.textTertiary),
          textAlign: TextAlign.center,
        ),
      );
    }

    // Honesty line (screen 09 footnote) — present in every state.
    children.add(const SizedBox(height: 8));
    children.add(
      Text(
        l10n.billing_noIdentityFootnote,
        style: NimnaText.micro.copyWith(color: tokens.textTertiary),
        textAlign: TextAlign.center,
      ),
    );

    // Store-mandated disclosure + Terms/Privacy — only beside the buy CTA,
    // and AFTER the honesty line (PM-confirmed order 2026-07-07): honesty →
    // disclosure → Terms · Privacy. {store} resolves to the platform store
    // brand name (a non-translated proper noun).
    if (isBuy) {
      final storeName = defaultTargetPlatform == TargetPlatform.android
          ? _kGooglePlay
          : _kAppStore;
      children.add(const SizedBox(height: 10));
      children.add(
        Text(
          l10n.billing_autoRenewDisclosure(storeName),
          style: text.bodySmall?.copyWith(color: tokens.textTertiary),
          textAlign: TextAlign.center,
        ),
      );
      children.add(const SizedBox(height: 6));
      children.add(_DisclosureLinks(tokens: tokens, l10n: l10n));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _restoreButton(AppLocalizations l10n, NimnaTokens tokens) {
    return TextButton(
      style: TextButton.styleFrom(foregroundColor: tokens.textSecondary),
      onPressed: (_busy || _restoring) ? null : _restore,
      child: Text(l10n.billing_restore),
    );
  }
}

/// One paywall feature row (hi-fi screen 09): `body` 500 title + `caption`
/// tertiary sub-line. Left-aligned; survives German-length strings by
/// wrapping.
class _FeaturePoint extends StatelessWidget {
  const _FeaturePoint({required this.title, required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          style: text.bodySmall?.copyWith(color: tokens.textTertiary),
        ),
      ],
    );
  }
}

/// Terms/Privacy link row beside the CTA (store-mandated; final labels,
/// USER-approved). Destinations land at S19 (website). The middot is a layout
/// separator, not a translated string.
class _DisclosureLinks extends StatelessWidget {
  const _DisclosureLinks({required this.tokens, required this.l10n});

  final NimnaTokens tokens;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _DisclosureLink(label: l10n.billing_termsLabel, tokens: tokens),
        // Decorative separator dot (no user-facing string — the app's dot
        // motif, not copy).
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 3,
          height: 3,
          decoration: BoxDecoration(
            color: tokens.textTertiary,
            borderRadius: BorderRadius.circular(NimnaRadius.full),
          ),
        ),
        _DisclosureLink(label: l10n.billing_privacyLabel, tokens: tokens),
      ],
    );
  }
}

class _DisclosureLink extends StatelessWidget {
  const _DisclosureLink({required this.label, required this.tokens});

  final String label;
  final NimnaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      link: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // TODO(S19): point at the website Terms/Privacy pages once they land
        // (the paywall carries no in-app document surface — USER 2026-07-07:
        // FAQ/legal live on the website at S19). Affordance only for now,
        // pending the same USER sign-off as the disclosure copy.
        onTap: () {},
        child: Text(
          label,
          style: text.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
      ),
    );
  }
}
