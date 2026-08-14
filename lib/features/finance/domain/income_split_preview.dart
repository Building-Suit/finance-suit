import 'package:meta/meta.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';

@immutable
class IncomeSplitPreviewRow {
  const IncomeSplitPreviewRow({
    required this.destinationAccountId,
    required this.amountMinor,
    required this.rule,
  });

  final String destinationAccountId;
  final int amountMinor;
  final IncomeAllocation rule;
}

@immutable
class IncomeSplitPreview {
  const IncomeSplitPreview({
    required this.primaryAmountMinor,
    required this.rows,
    this.extraWorkRoutedMinor = 0,
    this.extraWorkDestinationAccountId,
    this.error,
  });

  final int primaryAmountMinor;
  final List<IncomeSplitPreviewRow> rows;
  final int extraWorkRoutedMinor;
  final String? extraWorkDestinationAccountId;
  final String? error;

  bool get hasError => error != null;
}

abstract final class IncomeSplitCalculator {
  static IncomeSplitPreview preview({
    required int actualAmountMinor,
    required IncomeSourceKind kind,
    required List<IncomeAllocation> allocations,
    required bool includeExtraWorkInPercentage,
    required String? extraWorkDestinationAccountId,
    int extraWorkMinor = 0,
  }) {
    final protectedExtra =
        kind == IncomeSourceKind.salary && !includeExtraWorkInPercentage
        ? extraWorkMinor.clamp(0, actualAmountMinor).toInt()
        : 0;
    final originalBasis = actualAmountMinor - protectedExtra;
    var remaining = originalBasis;
    var primary = actualAmountMinor;
    final rows = <IncomeSplitPreviewRow>[];
    var percentageOrdinal = 0;

    for (final rule in allocations) {
      final amount = switch (rule.method) {
        IncomeAllocationMethod.percentage => _percentageAmount(
          basis:
              percentageOrdinal == 0 ||
                  rule.calculationBasis ==
                      IncomeAllocationCalculationBasis.original
              ? originalBasis
              : remaining,
          basisPoints: rule.percentageBasisPoints ?? 0,
        ),
        IncomeAllocationMethod.fixed => rule.fixedAmountMinor ?? 0,
      };
      if (rule.method == IncomeAllocationMethod.percentage) {
        percentageOrdinal += 1;
      }
      if (amount < 0 || amount > remaining) {
        return IncomeSplitPreview(
          primaryAmountMinor: primary,
          rows: rows,
          error: 'split_exceeds_available_income',
        );
      }
      remaining -= amount;
      primary -= amount;
      if (amount > 0) {
        rows.add(
          IncomeSplitPreviewRow(
            destinationAccountId: rule.destinationKey,
            amountMinor: amount,
            rule: rule,
          ),
        );
      }
    }

    var routedExtra = 0;
    if (protectedExtra > 0 && extraWorkDestinationAccountId != null) {
      routedExtra = protectedExtra;
      primary -= protectedExtra;
    }

    return IncomeSplitPreview(
      primaryAmountMinor: primary,
      rows: rows,
      extraWorkRoutedMinor: routedExtra,
      extraWorkDestinationAccountId: extraWorkDestinationAccountId,
    );
  }

  static int _percentageAmount({
    required int basis,
    required int basisPoints,
  }) => (basis * basisPoints) ~/ 10000;
}
