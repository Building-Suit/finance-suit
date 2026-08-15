import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/finance/data/installment_responsibility_repository.dart';
import 'package:work_tracker/features/finance/domain/installment_responsibility.dart';
import 'package:work_tracker/features/finance/presentation/providers/responsibility_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/responsibility_widgets.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// The shared view of one installment responsibility link, for both sides:
///
///   * the responsible network user reviews the sanitized terms and
///     schedule, accepts or rejects a pending request, and sends
///     reimbursements for accepted dues;
///   * the owner sees the same shared surface plus unlink and, for custom
///     links, per-due manual reimbursement recording.
///
/// Everything shown here comes from the narrow server DTO — never from the
/// owner's private plan, account, or transaction data.
class LinkedInstallmentScreen extends ConsumerStatefulWidget {
  const LinkedInstallmentScreen({super.key, required this.linkId});

  final String linkId;

  @override
  ConsumerState<LinkedInstallmentScreen> createState() =>
      _LinkedInstallmentScreenState();
}

class _LinkedInstallmentScreenState
    extends ConsumerState<LinkedInstallmentScreen> {
  bool _busy = false;

  Future<void> _respond({required bool accept}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(installmentResponsibilityRepositoryProvider);
    final result = accept
        ? await repo.acceptResponsibility(widget.linkId)
        : await repo.rejectResponsibility(widget.linkId);
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        invalidateResponsibilityData(ref);
        AppToast.success(
          context,
          accept ? l10n.respAcceptedToast : l10n.respRejectedToast,
        );
      },
      err: (failure) {
        invalidateResponsibilityData(ref);
        AppToast.error(context, failureMessage(context, failure));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detailsAsync = ref.watch(sharedLinkDetailsProvider(widget.linkId));
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(
        semanticTitle: l10n.respLinkedInstallmentsTitle,
      ),
      body: FinanceSuitFocusedBody(
        title: l10n.respLinkedInstallmentsTitle,
        child: AsyncView<SharedInstallmentLinkDetails>(
          value: detailsAsync,
          onRetry: () =>
              ref.invalidate(sharedLinkDetailsProvider(widget.linkId)),
          data: (details) => _buildDetails(context, l10n, details),
        ),
      ),
    );
  }

  Widget _buildDetails(
    BuildContext context,
    AppLocalizations l10n,
    SharedInstallmentLinkDetails details,
  ) {
    final theme = Theme.of(context);
    final colors = context.suitColors;
    final terms = details.current;
    final currency = terms.currencyCode;
    Money money(int minor) => Money(minor: minor, currencyCode: currency);

    return RefreshIndicator(
      onRefresh: () async =>
          ref.invalidate(sharedLinkDetailsProvider(widget.linkId)),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  terms.title,
                  style: theme.textTheme.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ResponsibilityStatusChip(status: details.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            details.viewerIsOwner
                ? l10n.respLinkedTo(details.counterpartyName)
                : l10n.respOwnerLabel(details.counterpartyName),
            style: theme.textTheme.bodyMedium,
          ),
          if (details.removedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.respLinkRemoved,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (!details.viewerIsOwner) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  l10n.respRecipientExplainer(details.counterpartyName),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          ],
          if (details.sharedNote != null && details.sharedNote!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${l10n.respSharedNoteLabel}: ${details.sharedNote}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (details.termsChanged) ...[
            const SizedBox(height: 12),
            Container(
              key: const Key('resp-terms-changed'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.warning.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                l10n.respTermsChangedBanner,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.warning.text,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _TermsCard(details: details),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.respReimbursementSection,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  ProtectedMoneyText(
                    l10n.respReimbursementReceivedTotal(
                      money(details.receivedTotalMinor).format(),
                      money(details.expectedTotalMinor).format(),
                    ),
                    style: theme.textTheme.bodyMedium,
                    interactive: false,
                  ),
                  if (details.pendingTotalMinor > 0)
                    ProtectedMoneyText(
                      '${l10n.respDueStatusPending}: '
                      '${money(details.pendingTotalMinor).format()}',
                      style: theme.textTheme.bodySmall,
                      interactive: false,
                    ),
                  ProtectedMoneyText(
                    l10n.respYourResponsibilityRemaining(
                      money(details.remainingTotalMinor).format(),
                    ),
                    style: theme.textTheme.bodySmall,
                    interactive: false,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.respScheduleSection, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final due in details.schedule)
                  _DueTile(
                    key: Key('resp-due-${due.sequenceNumber}'),
                    due: due,
                    currencyCode: currency,
                    action: _dueAction(details, due),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (details.canRespond) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('resp-reject'),
                    onPressed: _busy ? null : () => _respond(accept: false),
                    child: Text(l10n.networkReject),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('resp-accept'),
                    onPressed: _busy || details.termsChanged
                        ? null
                        : () => _respond(accept: true),
                    child: Text(l10n.networkAccept),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.respConsentHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (details.viewerIsOwner &&
              details.removedAt == null &&
              details.status != ResponsibilityLinkStatus.rejected)
            OutlinedButton(
              key: const Key('resp-unlink'),
              onPressed: _busy
                  ? null
                  : () => unlinkResponsibility(
                      context,
                      ref,
                      linkId: details.linkId,
                    ),
              child: Text(l10n.respUnlink),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget? _dueAction(
    SharedInstallmentLinkDetails details,
    ResponsibilityDueEntry due,
  ) {
    final l10n = AppLocalizations.of(context);
    if (!due.canReimburse) return null;
    if (details.viewerIsOwner &&
        details.linkType == ResponsibilityLinkType.custom &&
        details.isAccepted &&
        details.planStatus != 'cancelled') {
      return TextButton(
        key: Key('resp-record-${due.sequenceNumber}'),
        onPressed: () async {
          await recordCustomReimbursement(
            context,
            ref,
            details: details,
            due: due,
          );
        },
        child: Text(l10n.respRecordReimbursement),
      );
    }
    if (details.canSendReimbursement) {
      return TextButton(
        key: Key('resp-send-${due.sequenceNumber}'),
        onPressed: () async {
          await sendNetworkReimbursement(
            context,
            ref,
            details: details,
            due: due,
          );
        },
        child: Text(l10n.respSendReimbursement),
      );
    }
    return null;
  }
}

class _TermsCard extends StatelessWidget {
  const _TermsCard({required this.details});

  final SharedInstallmentLinkDetails details;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final terms = details.current;
    final currency = terms.currencyCode;
    Money money(int minor) => Money(minor: minor, currencyCode: currency);
    String rate() {
      final percent = (terms.interestRateBasisPoints / 100).toStringAsFixed(2);
      final period = terms.interestRatePeriod == 'annual'
          ? l10n.purchaseRatePerYear
          : l10n.purchaseRatePerMonth;
      return '$percent% · $period';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.respTermsSection, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _TermRow(label: l10n.purchaseFacility, value: terms.facilityName),
            if (terms.categoryName != null)
              _TermRow(label: l10n.txCategory, value: terms.categoryName!),
            if (terms.purchasedOn != null)
              _TermRow(
                label: l10n.purchaseDateLabel,
                value: terms.purchasedOn!.toIso(),
              ),
            _TermRow(
              label: l10n.purchasePrice,
              value: money(terms.purchasePriceMinor).format(),
              protected: true,
            ),
            if (terms.downPaymentMinor > 0)
              _TermRow(
                label: l10n.purchaseDownPayment,
                value: money(terms.downPaymentMinor).format(),
                protected: true,
              ),
            _TermRow(
              label: l10n.purchaseFinancedPrincipal,
              value: money(terms.financedPrincipalMinor).format(),
              protected: true,
            ),
            if (terms.financingFeesMinor > 0)
              _TermRow(
                label: l10n.purchaseFinancingFees,
                value: money(terms.financingFeesMinor).format(),
                protected: true,
              ),
            if (terms.interestMinor > 0)
              _TermRow(
                label: l10n.respTermInterest,
                value: money(terms.interestMinor).format(),
                protected: true,
              ),
            _TermRow(
              label: l10n.purchaseTotalPayable,
              value: money(terms.totalPayableMinor).format(),
              protected: true,
            ),
            if (terms.interestRateBasisPoints > 0)
              _TermRow(label: l10n.respTermRate, value: rate()),
            _TermRow(
              label: l10n.purchaseInstallmentCount,
              value: '${terms.installmentCount}',
            ),
            if (terms.typicalInstallmentMinor != null)
              _TermRow(
                label: l10n.purchaseMonthlyAmount,
                value: terms.typicalInstallment!.format(),
                protected: true,
              ),
            _TermRow(
              label: l10n.respTermAlreadyPaid,
              value: '${terms.paidInstallmentCount}',
            ),
            _TermRow(
              label: l10n.respTermRemainingCount,
              value: '${terms.remainingCount}',
            ),
            _TermRow(
              label: l10n.respTermRemainingTotal,
              value: terms.remainingTotal.format(),
              protected: true,
            ),
            if (terms.firstDueOn != null)
              _TermRow(
                label: l10n.purchaseFirstDueDate,
                value: terms.firstDueOn!.toIso(),
              ),
            if (terms.nextDueOn != null)
              _TermRow(
                label: l10n.respTermNextDue,
                value: terms.nextDueOn!.toIso(),
              ),
            if (terms.finalDueOn != null)
              _TermRow(
                label: l10n.respTermFinalDue,
                value: terms.finalDueOn!.toIso(),
              ),
          ],
        ),
      ),
    );
  }
}

class _TermRow extends StatelessWidget {
  const _TermRow({
    required this.label,
    required this.value,
    this.protected = false,
  });

  final String label;
  final String value;
  final bool protected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueText = Text(
      value,
      style: theme.textTheme.bodySmall,
      textAlign: TextAlign.end,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: protected
                ? ProtectedMoney(interactive: false, child: valueText)
                : valueText,
          ),
        ],
      ),
    );
  }
}

class _DueTile extends StatelessWidget {
  const _DueTile({
    super.key,
    required this.due,
    required this.currencyCode,
    this.action,
  });

  final ResponsibilityDueEntry due;
  final String currencyCode;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.suitColors;
    final statusLabel = switch (due.reimbursementStatus) {
      DueReimbursementStatus.notPaid => l10n.respDueStatusNotPaid,
      DueReimbursementStatus.pending => l10n.respDueStatusPending,
      DueReimbursementStatus.partial => l10n.respDueStatusPartial,
      DueReimbursementStatus.received => l10n.respDueStatusReceived,
    };
    final statusColor = switch (due.reimbursementStatus) {
      DueReimbursementStatus.received => colors.success.text,
      DueReimbursementStatus.pending => colors.warning.text,
      DueReimbursementStatus.partial => colors.warning.text,
      DueReimbursementStatus.notPaid => Theme.of(
        context,
      ).colorScheme.onSurfaceVariant,
    };
    return ListTile(
      dense: true,
      leading: Text('#${due.sequenceNumber}'),
      title: ProtectedMoney(
        interactive: false,
        child: Text(
          Money(minor: due.amountMinor, currencyCode: currencyCode).format(),
        ),
      ),
      subtitle: Text(
        '${due.dueOn.toIso()} · $statusLabel',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: statusColor),
      ),
      trailing: action,
    );
  }
}
