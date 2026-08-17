import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/finance/domain/facility_payment_component.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Compact horizontal carousel of the two payable calendar months.
///
/// Each month loads independently, so a slow or failing month never blocks
/// the other one. The active page drives the detailed breakdown below it.
class FacilityDueMonthCarousel extends ConsumerStatefulWidget {
  const FacilityDueMonthCarousel({
    super.key,
    required this.accountId,
    required this.months,
    required this.activeIndex,
    required this.onMonthChanged,
    required this.onPayMonth,
  });

  final String accountId;
  final List<FacilityDueMonth> months;
  final int activeIndex;
  final ValueChanged<int> onMonthChanged;
  final ValueChanged<FacilityDueMonth> onPayMonth;

  @override
  ConsumerState<FacilityDueMonthCarousel> createState() =>
      _FacilityDueMonthCarouselState();
}

class _FacilityDueMonthCarouselState
    extends ConsumerState<FacilityDueMonthCarousel> {
  late final PageController _controller = PageController(
    initialPage: widget.activeIndex,
    // The next card deliberately peeks in so the second period is
    // discoverable without a full-width swipe.
    viewportFraction: 0.86,
  );

  /// Reported page heights. The viewport takes the tallest one, so the
  /// cards are never clipped: a hardcoded height broke at larger text
  /// scales, cutting the payment button in half.
  ///
  /// Each card is rendered with the viewport as its minimum height (so the
  /// two months always read as one equal row), which means a report is
  /// max(natural, viewport): the viewport can grow but not shrink while
  /// this state lives. That bias is only cosmetic whitespace — content can
  /// never be clipped by it — and the map is reset whenever the months or
  /// the text scale change.
  final Map<int, double> _pageHeights = {};

  /// The text scale the current measurements were taken at.
  TextScaler? _measuredScale;

  /// Before the first report the viewport uses this guess for one frame;
  /// it is corrected as soon as a page reports its real height.
  static const _fallbackHeight = 186.0;

  double get _viewportHeight => _pageHeights.isEmpty
      ? _fallbackHeight
      : _pageHeights.values.reduce(math.max);

  void _reportHeight(int index, double height) {
    if (_pageHeights[index] == height) return;
    setState(() => _pageHeights[index] = height);
  }

  @override
  void didUpdateWidget(covariant FacilityDueMonthCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A month rollover replaces the pages; their old heights must not keep
    // inflating the viewport.
    if (!listEquals(
      [for (final m in oldWidget.months) m.key],
      [for (final m in widget.months) m.key],
    )) {
      _pageHeights.clear();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Heights measured at one text scale are meaningless at another; a
    // lowered scale would otherwise leave permanently inflated cards.
    final scale = MediaQuery.textScalerOf(context);
    if (_measuredScale != null && _measuredScale != scale) {
      _pageHeights.clear();
    }
    _measuredScale = scale;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('facility-due-carousel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _viewportHeight,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.months.length,
            onPageChanged: widget.onMonthChanged,
            itemBuilder: (context, index) {
              final month = widget.months[index];
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                // The page is given the viewport's tight height, so the
                // card measures itself unbounded and reports back instead
                // of being forced to clip its own content.
                child: OverflowBox(
                  alignment: AlignmentDirectional.topStart,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: _ReportHeight(
                    onHeight: (height) => _reportHeight(index, height),
                    child: _MonthCard(
                      key: Key(
                        'facility-due-card-'
                        '${month.isCurrentMonth ? 'current' : 'next'}',
                      ),
                      accountId: widget.accountId,
                      month: month,
                      minHeight: _viewportHeight,
                      isActive: index == widget.activeIndex,
                      onPay: () => widget.onPayMonth(month),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        _PageIndicator(
          count: widget.months.length,
          activeIndex: widget.activeIndex,
        ),
      ],
    );
  }
}

/// Reports the laid-out height of its child whenever it changes.
class _ReportHeight extends SingleChildRenderObjectWidget {
  const _ReportHeight({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ReportHeightRenderObject(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _ReportHeightRenderObject renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _ReportHeightRenderObject extends RenderProxyBox {
  _ReportHeightRenderObject(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (_reported == height) return;
    _reported = height;
    // Reporting mutates state, so it must wait for the frame to finish.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onHeight(height);
    });
  }
}

class _MonthCard extends ConsumerWidget {
  const _MonthCard({
    super.key,
    required this.accountId,
    required this.month,
    required this.minHeight,
    required this.isActive,
    required this.onPay,
  });

  final String accountId;
  final FacilityDueMonth month;

  /// The current viewport height: the card fills at least the tallest
  /// sibling so both months read as one row even when one has less content.
  final double minHeight;
  final bool isActive;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = context.suitColors;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final monthLabel = DateFormat.MMM(locale).format(month.start.toDateTime());
    final periodLabel = month.isCurrentMonth
        ? l10n.dueMonthCurrent
        : l10n.dueMonthNext;
    final async = ref.watch(
      facilityMonthDueBreakdownProvider((
        accountId: accountId,
        monthStartIso: month.key,
      )),
    );

    // The card sizes itself to its content — a fixed height clipped the
    // payment button as soon as the device text scale grew — and never
    // shrinks below the tallest sibling so the two cards stay one row.
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isActive ? colors.brandSurface : colors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isActive ? colors.primary : colors.borderSubtle,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      periodLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: isActive
                            ? colors.onBrandSurface
                            : colors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    monthLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: isActive
                          ? colors.onBrandSurface
                          : colors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              async.when(
                loading: () => const SizedBox(
                  height: 96,
                  child: Center(
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (_, _) => _MonthError(
                  onRetry: () => ref.invalidate(
                    facilityMonthDueBreakdownProvider((
                      accountId: accountId,
                      monthStartIso: month.key,
                    )),
                  ),
                ),
                data: (breakdown) => _MonthBody(
                  month: month,
                  breakdown: breakdown,
                  isActive: isActive,
                  periodLabel: periodLabel,
                  monthLabel: monthLabel,
                  onPay: onPay,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthBody extends StatelessWidget {
  const _MonthBody({
    required this.month,
    required this.breakdown,
    required this.isActive,
    required this.periodLabel,
    required this.monthLabel,
    required this.onPay,
  });

  final FacilityDueMonth month;
  final FacilityDueBreakdown breakdown;
  final bool isActive;
  final String periodLabel;
  final String monthLabel;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = context.suitColors;
    final onSurface = isActive ? colors.onBrandSurface : colors.textPrimary;
    String money(int minor) =>
        Money(minor: minor, currencyCode: breakdown.currencyCode).format();

    if (breakdown.hasNoDues) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            l10n.dueMonthNoDues,
            style: theme.textTheme.bodyMedium?.copyWith(color: onSurface),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    Widget row(String label, int minor, {bool emphasize = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style:
                  (emphasize
                          ? theme.textTheme.bodyMedium
                          : theme.textTheme.bodySmall)
                      ?.copyWith(
                        color: onSurface,
                        fontWeight: emphasize ? FontWeight.w700 : null,
                      ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Expanded + end alignment keeps the amounts flush in one column;
          // the FittedBox only shrinks a figure that a large text scale
          // would otherwise overflow.
          Expanded(
            flex: 3,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: ProtectedMoneyText(
                  money(minor),
                  interactive: false,
                  style:
                      (emphasize
                              ? theme.textTheme.bodyMedium
                              : theme.textTheme.bodySmall)
                          ?.copyWith(
                            color: onSurface,
                            fontWeight: emphasize ? FontWeight.w700 : null,
                          ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final settled = breakdown.isFullyPaid;
    return Semantics(
      label: l10n.dueMonthSemanticCard(
        periodLabel,
        monthLabel,
        money(breakdown.remainingMinor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(l10n.dueBreakdownTotalDue, breakdown.totalDueMinor),
          row(l10n.dueBreakdownPaid, breakdown.paidMinor),
          row(
            l10n.dueBreakdownLeftToPay,
            breakdown.remainingMinor,
            emphasize: true,
          ),
          const SizedBox(height: 12),
          if (settled)
            Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: colors.success.icon),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.paymentRowPaid,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.success.text,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          else
            FilledButton(
              key: Key(
                'facility-due-card-pay-'
                '${month.isCurrentMonth ? 'current' : 'next'}',
              ),
              onPressed: onPay,
              child: Text(
                l10n.dueMonthMakePayments,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthError extends StatelessWidget {
  const _MonthError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.commonError, style: Theme.of(context).textTheme.bodySmall),
          TextButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
        ],
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.count, required this.activeIndex});

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final colors = context.suitColors;
    return Row(
      key: const Key('facility-due-page-indicator'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < count; index++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 6,
            width: index == activeIndex ? 18 : 6,
            decoration: BoxDecoration(
              color: index == activeIndex
                  ? colors.primary
                  : colors.borderStrong,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}
