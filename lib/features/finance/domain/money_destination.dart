import 'package:flutter/foundation.dart';

/// Where money can be sent from a destination selector: one of the user's
/// own accounts, or a connected person from their Finance Suit network.
///
/// A network contact is a private transfer destination identity — it is NOT
/// an account the user owns, so it never carries a balance and is never a
/// funding source. Keeping the two shapes in one sealed type stops forms
/// from smuggling a connection id into an account field or vice versa.
@immutable
sealed class MoneyDestination {
  const MoneyDestination();
}

/// One of the current user's own accounts.
class OwnAccountDestination extends MoneyDestination {
  const OwnAccountDestination(this.accountId);

  final String accountId;

  @override
  bool operator ==(Object other) =>
      other is OwnAccountDestination && other.accountId == accountId;

  @override
  int get hashCode => Object.hash(runtimeType, accountId);
}

/// A connected network contact, addressed by the connection id and shown by
/// the current user's private alias.
class NetworkContactDestination extends MoneyDestination {
  const NetworkContactDestination(this.connectionId, {this.alias = ''});

  final String connectionId;
  final String alias;

  @override
  bool operator ==(Object other) =>
      other is NetworkContactDestination && other.connectionId == connectionId;

  @override
  int get hashCode => Object.hash(runtimeType, connectionId);
}

/// Presentation-only sentinel for the disabled group rows ("My accounts" /
/// "My network") inside destination pickers. Never a real selection and never
/// persisted; it lives here only because a sealed type cannot be extended
/// outside its library. Identity equality keeps it from matching anything.
class DestinationPickerHeader extends MoneyDestination {
  const DestinationPickerHeader(this.label);

  final String label;
}
