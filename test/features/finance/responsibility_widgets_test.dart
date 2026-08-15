import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/installment_responsibility.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/providers/responsibility_providers.dart';
import 'package:work_tracker/features/finance/presentation/screens/linked_installment_screen.dart';
import 'package:work_tracker/features/finance/presentation/widgets/responsibility_widgets.dart';
import 'package:work_tracker/features/network/domain/network_models.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

final _contact = NetworkContact(
  connectionId: 'connection-1',
  otherUserId: 'user-2',
  localAlias: 'Wife',
  realDisplayName: 'Mona Ahmed',
  email: 'mona@example.com',
  connectedAt: DateTime.utc(2026, 8, 1),
);

const _ownerBank = AccountBalance(
  accountId: 'asset-1',
  name: 'Bank',
  accountType: AccountType.current,
  currencyCode: 'EGP',
  isDefault: true,
  isArchived: false,
  allowNegativeBalance: false,
  openingBalanceMinor: 500000,
  balanceMinor: 500000,
  totalIncomingMinor: 0,
  totalOutgoingMinor: 0,
);

SharedInstallmentLinkDetails _details({
  String status = 'pending',
  String viewerRole = 'responsible',
  String linkType = 'network',
  bool termsChanged = false,
}) => SharedInstallmentLinkDetails.fromJson({
  'link': {
    'id': 'link-1',
    'link_type': linkType,
    'status': status,
    'viewer_role': viewerRole,
    'counterparty_name': 'Tarek',
    'shared_note': null,
    'responsibility_from_sequence': 1,
    'plan_revision_at_request': 1,
    'requested_at': '2026-08-14T09:00:00Z',
    'accepted_at': status == 'accepted' ? '2026-08-14T10:00:00Z' : null,
    'rejected_at': null,
    'removed_at': null,
    'connection_active': true,
  },
  'snapshot': {'title': 'Samsung TV', 'currency_code': 'EGP'},
  'current': {
    'title': 'Samsung TV',
    'owner_display_name': 'Tarek Owner',
    'facility_name': 'CIB Gold',
    'facility_type': 'credit_card',
    'category_name': 'Electronics',
    'purchased_on': '2026-06-01',
    'first_due_on': '2026-06-25',
    'currency_code': 'EGP',
    'purchase_price_minor': 1300000,
    'down_payment_minor': 100000,
    'financed_principal_minor': 1200000,
    'financing_fees_minor': 55000,
    'interest_minor': 55000,
    'total_payable_minor': 1255000,
    'pricing_method': 'interest_rate',
    'interest_rate_basis_points': 250,
    'interest_rate_period': 'monthly',
    'interest_method': 'flat',
    'installment_count': 12,
    'paid_installment_count': 2,
    'responsibility_from_sequence': 1,
    'remaining_count': 10,
    'remaining_total_minor': 1000000,
    'next_due_on': '2026-08-25',
    'final_due_on': '2027-05-25',
    'typical_installment_minor': 100000,
    'plan_status': 'active',
    'terms_changed': termsChanged,
  },
  'schedule': [
    {
      'due_id': 'due-1',
      'sequence_number': 1,
      'due_on': '2026-08-25',
      'amount_minor': 100000,
      'received_minor': 0,
      'pending_minor': 0,
      'remaining_minor': 100000,
      'reimbursement_status': 'not_paid',
    },
    {
      'due_id': 'due-2',
      'sequence_number': 2,
      'due_on': '2026-09-25',
      'amount_minor': 100000,
      'received_minor': 100000,
      'pending_minor': 0,
      'remaining_minor': 0,
      'reimbursement_status': 'received',
    },
  ],
  'reimbursement_summary': {
    'expected_total_minor': 200000,
    'received_total_minor': 100000,
    'pending_total_minor': 0,
    'remaining_total_minor': 100000,
  },
});

Future<void> _pumpLinkedScreen(
  WidgetTester tester,
  SharedInstallmentLinkDetails details,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedLinkDetailsProvider.overrideWith((ref, linkId) async => details),
        accountBalancesProvider.overrideWith((ref) async => [_ownerBank]),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LinkedInstallmentScreen(linkId: 'link-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('responsibility target sheet', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      List<NetworkContact> contacts = const [],
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ResponsibilityTargetSheet(
                contacts: contacts,
                showOngoingScopeNote: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('defaults to a custom person and requires a name', (
      tester,
    ) async {
      await pumpSheet(tester);
      expect(find.byKey(const Key('resp-custom-name')), findsOneWidget);
      expect(
        find.textContaining('remaining unpaid installments'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('resp-link-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose a name between 1 and 80 characters'),
        findsOneWidget,
      );
    });

    testWidgets('network mode without contacts points to Manage Network', (
      tester,
    ) async {
      await pumpSheet(tester);
      await tester.tap(find.text('Finance Suit Network'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Add someone to your network first'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('resp-manage-network')), findsOneWidget);
    });

    testWidgets('network mode lists contacts by their private alias', (
      tester,
    ) async {
      await pumpSheet(tester, contacts: [_contact]);
      await tester.tap(find.text('Finance Suit Network'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('resp-network-contact')), findsOneWidget);
      await tester.tap(find.byKey(const Key('resp-network-contact')));
      await tester.pumpAndSettle();
      expect(find.text('Wife'), findsWidgets);
      expect(find.text('Mona Ahmed'), findsNothing);
    });
  });

  group('recipient review', () {
    testWidgets('a pending request shows full terms and both decisions', (
      tester,
    ) async {
      await _pumpLinkedScreen(tester, _details());

      expect(find.text('Samsung TV'), findsOneWidget);
      expect(find.text('Owner: Tarek'), findsOneWidget);
      expect(find.textContaining('CIB Gold'), findsOneWidget);
      expect(find.text('Purchase price'), findsOneWidget);
      expect(find.text('Total payable'), findsOneWidget);
      expect(find.text('Installments already paid'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('resp-accept')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('resp-due-1')), findsOneWidget);
      expect(find.byKey(const Key('resp-due-2')), findsOneWidget);
      expect(find.byKey(const Key('resp-accept')), findsOneWidget);
      expect(find.byKey(const Key('resp-reject')), findsOneWidget);

      // Sanitized surface only: nothing about limits or balances leaks.
      expect(find.textContaining('Credit limit'), findsNothing);
      expect(find.textContaining('Available credit'), findsNothing);
    });

    testWidgets('changed terms block acceptance with a warning', (
      tester,
    ) async {
      await _pumpLinkedScreen(tester, _details(termsChanged: true));
      expect(find.byKey(const Key('resp-terms-changed')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('resp-accept')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final accept = tester.widget<FilledButton>(
        find.byKey(const Key('resp-accept')),
      );
      expect(accept.onPressed, isNull);
    });

    testWidgets('an accepted link offers per-due reimbursement sending', (
      tester,
    ) async {
      await _pumpLinkedScreen(tester, _details(status: 'accepted'));
      expect(find.byKey(const Key('resp-accept')), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('resp-send-1')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('resp-send-1')), findsOneWidget);
      // A fully reimbursed due offers nothing.
      expect(find.byKey(const Key('resp-send-2')), findsNothing);

      await tester.tap(find.byKey(const Key('resp-send-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('resp-reimb-amount')), findsOneWidget);
      expect(find.byKey(const Key('resp-reimb-account')), findsOneWidget);
    });
  });

  group('owner view', () {
    testWidgets('a custom link records reimbursements and can unlink', (
      tester,
    ) async {
      await _pumpLinkedScreen(
        tester,
        _details(status: 'accepted', viewerRole: 'owner', linkType: 'custom'),
      );
      expect(find.text('Linked to Tarek'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('resp-unlink')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('resp-record-1')), findsOneWidget);
      expect(find.byKey(const Key('resp-record-2')), findsNothing);
      expect(find.byKey(const Key('resp-unlink')), findsOneWidget);

      await tester.tap(find.byKey(const Key('resp-record-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('resp-reimb-amount')), findsOneWidget);
      expect(find.byKey(const Key('resp-reimb-date')), findsOneWidget);
    });

    testWidgets('an owner cannot respond to their own request', (tester) async {
      await _pumpLinkedScreen(tester, _details(viewerRole: 'owner'));
      expect(find.byKey(const Key('resp-accept')), findsNothing);
      expect(find.byKey(const Key('resp-reject')), findsNothing);
    });
  });

  group('responsibility status labels', () {
    test('cover the exact owner chip wording states', () {
      InstallmentResponsibilitySummary summary(
        ResponsibilityLinkStatus status,
      ) => InstallmentResponsibilitySummary(
        planId: 'plan-1',
        linkId: 'link-1',
        linkType: ResponsibilityLinkType.network,
        status: status,
        displayName: 'Wife',
        fromSequence: 1,
        expectedTotalMinor: 0,
        receivedTotalMinor: 0,
        pendingTotalMinor: 0,
        expectedRemainingMinor: 0,
      );
      expect(summary(ResponsibilityLinkStatus.accepted).isAccepted, isTrue);
      expect(summary(ResponsibilityLinkStatus.pending).isPending, isTrue);
      expect(summary(ResponsibilityLinkStatus.rejected).isRejected, isTrue);
    });
  });
}
