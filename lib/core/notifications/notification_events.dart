import 'package:flutter/foundation.dart';

/// The client mirror of `app_core.notification_event_catalog`.
///
/// Notifications are stored with a stable machine key and localized at render
/// time, so a machine key must never reach the user. Anything the server sends
/// that this build does not know about falls back to
/// [NotificationEvent.unknown] and renders as a generic entry rather than
/// leaking `credit_card.statement_due_soon` into the UI.
enum NotificationCategory { due, overdue, payment, network, system, security }

enum NotificationEvent {
  creditCardStatementDueSoon(
    'credit_card.statement_due_soon',
    NotificationCategory.due,
  ),
  creditCardStatementDueToday(
    'credit_card.statement_due_today',
    NotificationCategory.due,
  ),
  creditCardStatementOverdue(
    'credit_card.statement_overdue',
    NotificationCategory.overdue,
  ),
  installmentDueSoon('installment.due_soon', NotificationCategory.due),
  installmentDueToday('installment.due_today', NotificationCategory.due),
  installmentOverdue('installment.overdue', NotificationCategory.overdue),
  bnplDueSoon('bnpl.due_soon', NotificationCategory.due),
  bnplDueToday('bnpl.due_today', NotificationCategory.due),
  bnplOverdue('bnpl.overdue', NotificationCategory.overdue),
  facilityPaymentRecorded(
    'facility.payment_recorded',
    NotificationCategory.payment,
  ),
  networkAddRequestReceived(
    'network.add_request_received',
    NotificationCategory.network,
  ),
  networkAddRequestAccepted(
    'network.add_request_accepted',
    NotificationCategory.network,
  ),
  networkTransferReceived(
    'network.transfer_received',
    NotificationCategory.network,
  ),
  networkTransferAccepted(
    'network.transfer_accepted',
    NotificationCategory.network,
  ),
  networkTransferDeclined(
    'network.transfer_declined',
    NotificationCategory.network,
  ),
  installmentLinkRequestReceived(
    'installment_link.request_received',
    NotificationCategory.network,
  ),
  installmentLinkAccepted(
    'installment_link.accepted',
    NotificationCategory.network,
  ),
  installmentLinkDeclined(
    'installment_link.declined',
    NotificationCategory.network,
  ),
  developerTest('system.developer_test', NotificationCategory.system),
  unknown('', NotificationCategory.system);

  const NotificationEvent(this.key, this.category);

  final String key;
  final NotificationCategory category;

  static final Map<String, NotificationEvent> _byKey = {
    for (final event in NotificationEvent.values)
      if (event != NotificationEvent.unknown) event.key: event,
  };

  static NotificationEvent fromKey(String? key) =>
      _byKey[key] ?? NotificationEvent.unknown;

  bool get isDue =>
      category == NotificationCategory.due ||
      category == NotificationCategory.overdue;
}

/// Routes a notification is allowed to open.
///
/// A notification payload is addressing, not authorization: this only decides
/// that a destination is a real Finance Suit screen. The target itself is
/// still read through the normal repositories under RLS, so a route that
/// points at another user's entity resolves to nothing rather than to data.
@immutable
abstract final class NotificationRoutes {
  static final List<RegExp> _allowed = [
    RegExp(r'^/home$'),
    RegExp(r'^/money$'),
    RegExp(r'^/money/network$'),
    RegExp(r'^/money/facilities/[0-9a-fA-F-]{36}$'),
    RegExp(r'^/money/accounts/[0-9a-fA-F-]{36}$'),
    RegExp(r'^/money/linked/[0-9a-fA-F-]{36}$'),
    RegExp(r'^/settings$'),
  ];

  /// The safe destination for [route], or null when there is nothing valid to
  /// open. A malformed or unknown route never navigates and never crashes.
  static String? resolve(String? route) {
    final value = route?.trim();
    if (value == null || value.isEmpty || value.length > 512) return null;
    // Reject anything that could escape the app's own router.
    if (!value.startsWith('/') || value.startsWith('//')) return null;
    if (value.contains('..') || value.contains('?') || value.contains('#')) {
      return null;
    }
    for (final pattern in _allowed) {
      if (pattern.hasMatch(value)) return value;
    }
    return null;
  }
}
