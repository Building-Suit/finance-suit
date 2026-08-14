import 'package:flutter/material.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/money_destination.dart';
import 'package:work_tracker/features/network/domain/network_models.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// The canonical destination picker: the caller's own accounts grouped under
/// "My accounts" and, when allowed, connected people under "My network".
///
/// Network rows show only the private alias and a person glyph — never a
/// balance, because a network contact is a transfer destination identity and
/// not an account the user can see into. Selection is returned as a typed
/// [MoneyDestination] so forms cannot confuse the two shapes.
class DestinationSelectionField extends StatelessWidget {
  const DestinationSelectionField({
    super.key,
    required this.accounts,
    required this.onChanged,
    required this.decoration,
    this.contacts = const [],
    this.initialValue,
    this.validator,
  });

  /// Eligible own accounts, already filtered by the caller (role, currency,
  /// archived, excluded source account).
  final List<AccountBalance> accounts;

  /// Eligible network contacts. Pass an empty list in flows where network
  /// destinations are not allowed (expense funding, transfer sources, ...).
  final List<NetworkContact> contacts;

  final MoneyDestination? initialValue;
  final ValueChanged<MoneyDestination?> onChanged;
  final InputDecoration decoration;
  final String? Function(MoneyDestination?)? validator;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final grouped = contacts.isNotEmpty;
    final items = <DropdownMenuItem<MoneyDestination>>[
      if (grouped)
        DropdownMenuItem(
          value: DestinationPickerHeader(l10n.networkGroupMyAccounts),
          enabled: false,
          child: Text(
            l10n.networkGroupMyAccounts,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      for (final account in accounts)
        DropdownMenuItem(
          value: OwnAccountDestination(account.accountId),
          child: ProtectedMoney(
            interactive: false,
            child: Text('${account.name} (${account.balance.format()})'),
          ),
        ),
      if (grouped) ...[
        DropdownMenuItem(
          value: DestinationPickerHeader(l10n.networkGroupMyNetwork),
          enabled: false,
          child: Text(
            l10n.networkGroupMyNetwork,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        for (final contact in contacts)
          DropdownMenuItem(
            value: NetworkContactDestination(
              contact.connectionId,
              alias: contact.localAlias,
            ),
            child: Row(
              children: [
                const FinanceSuitIcon(FinanceSuitIcons.person, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${contact.localAlias} — ${l10n.networkContactLabel}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    ];
    return AppSelectionField<MoneyDestination>(
      initialValue: initialValue,
      decoration: decoration,
      items: items,
      onChanged: onChanged,
      validator: validator,
    );
  }
}
