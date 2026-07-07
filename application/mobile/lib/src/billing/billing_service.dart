import 'entitlement_source.dart';

/// The pure-Dart billing orchestrator (S17), injected into [NimnaServices]
/// and consumed by the creation gate (`create_line_entry.dart`) and the
/// paywall. It holds no store SDK itself — it delegates every store touch to
/// the [EntitlementSource] seam, so it is fully unit- and widget-testable
/// against a fake.
///
/// It is deliberately NOT a [ChangeNotifier] and caches NO entitlement flag:
/// permanence is structural (spec §10). Nothing observes entitlement
/// reactively — the send/receive/session path and the channel list never
/// reference this service, and a lapse can only be discovered at the next
/// creation-time query.
class BillingService {
  BillingService(this._source);

  final EntitlementSource _source;

  /// THE gate (create_line_entry.dart::startCreateLine). `true` ONLY when the
  /// store's signed on-device cache confirms an active creation subscription.
  /// [EntitlementStatus.unresolved] (offline / store-unavailable) is
  /// fail-closed to `false` → the paywall, which then renders the calm
  /// reconnect state (never blocking USE of existing channels — spec §10,
  /// SESSION-17 CODE decision).
  Future<bool> hasActiveCreationEntitlement() async =>
      await _source.hasActiveCreationEntitlement() == EntitlementStatus.active;

  /// The paywall's tri-state query — distinguishes "no subscription" (buy
  /// state) from "couldn't resolve" (reconnect state).
  Future<EntitlementStatus> entitlementStatus() =>
      _source.hasActiveCreationEntitlement();

  /// The store's localized price string, or `null` if it can't be fetched.
  /// Rendered verbatim into the CTA — never a hardcoded number (spec §10).
  Future<String?> localizedPrice() => _source.localizedPrice();

  /// Launches the platform subscription sheet (F9.3).
  Future<PurchaseOutcome> purchaseCreationSubscription() =>
      _source.purchaseCreationSubscription();

  /// Store-mediated restore (F9.5) — the only path back to creation after a
  /// reinstall or panic wipe (spec §10).
  Future<RestoreOutcome> restore() => _source.restore();
}
