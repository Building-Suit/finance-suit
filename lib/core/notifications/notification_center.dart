import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/routing/finance_suit_menu.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/notifications/notification_events.dart';
import 'package:work_tracker/core/notifications/notification_feed.dart';
import 'package:work_tracker/core/notifications/notifications_repository.dart';
import 'package:work_tracker/core/widgets/app_money_text.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Logical-end counterpart to [FinanceSuitMenu]. It reuses the menu's motion,
/// scrim, width and focus semantics while presenting the user's own
/// notification history.
abstract final class NotificationCenter {
  static final ValueNotifier<double> pageProgress = ValueNotifier<double>(0);
  static _NotificationCenterRoute? _activeRoute;
  static bool get isOpen => _activeRoute != null;

  /// The notification center opens from the logical end edge. The page moves
  /// away from that edge, so this resolves to left in LTR and right in RTL.
  static double pagePlaneDirection(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl ? 1 : -1;

  static Future<void> close() async {
    final route = _activeRoute;
    if (route == null) return;
    route.navigator?.pop();
    await route.completed;
  }

  static Future<void> open(BuildContext context) async {
    if (isOpen) return;
    // A menu is modal and already blocks the bell, but this also protects
    // programmatic callers: exactly one app-level drawer may be open.
    if (FinanceSuitMenu.isOpen) await FinanceSuitMenu.close();
    if (!context.mounted) return;
    final theme = Theme.of(context);
    final route = _NotificationCenterRoute(
      reduceMotion: MediaQuery.of(context).disableAnimations,
      scrim: theme.colorScheme.scrim.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.64 : 0.48,
      ),
      label: AppLocalizations.of(context).setNotificationsSection,
      dismissLabel: AppLocalizations.of(context).commonClose,
      onDisposed: () => _activeRoute = null,
    );
    _activeRoute = route;
    await Navigator.of(context, rootNavigator: true).push<void>(route);
  }
}

class _NotificationCenterRoute extends PopupRoute<void> {
  _NotificationCenterRoute({
    required this.reduceMotion,
    required this.scrim,
    required this.label,
    required this.dismissLabel,
    required this.onDisposed,
  });

  final bool reduceMotion;
  final Color scrim;
  final String label;
  final String dismissLabel;
  final VoidCallback onDisposed;
  CurvedAnimation? _pagePlaneCurve;

  @override
  TickerFuture didPush() {
    if (!reduceMotion) {
      _pagePlaneCurve = CurvedAnimation(
        parent: animation!,
        curve: FinanceSuitMenu.standardCurve,
        reverseCurve: FinanceSuitMenu.standardCurve.flipped,
      );
      animation!.addListener(_syncPagePlane);
    }
    return super.didPush();
  }

  void _syncPagePlane() {
    final curve = _pagePlaneCurve;
    if (curve != null) {
      NotificationCenter.pageProgress.value = curve.value.clamp(0.0, 1.0);
    }
  }

  @override
  Color? get barrierColor => scrim;
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => dismissLabel;
  @override
  Duration get transitionDuration => reduceMotion
      ? FinanceSuitMenu.reducedMotionDuration
      : FinanceSuitMenu.openDuration;
  @override
  Duration get reverseTransitionDuration => reduceMotion
      ? FinanceSuitMenu.reducedMotionDuration
      : FinanceSuitMenu.closeDuration;

  @override
  Widget buildModalBarrier() {
    final scrimEnd = reduceMotion
        ? 1.0
        : FinanceSuitMenu.scrimDuration.inMilliseconds /
              FinanceSuitMenu.openDuration.inMilliseconds;
    final color = animation!.drive(
      ColorTween(
        begin: scrim.withValues(alpha: 0),
        end: scrim,
      ).chain(CurveTween(curve: Interval(0, scrimEnd))),
    );
    return AnimatedModalBarrier(
      color: color,
      dismissible: barrierDismissible,
      semanticsLabel: barrierLabel,
      barrierSemanticsDismissible: semanticsDismissible,
    );
  }

  @override
  void dispose() {
    animation?.removeListener(_syncPagePlane);
    _pagePlaneCurve?.dispose();
    NotificationCenter.pageProgress.value = 0;
    onDisposed();
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Semantics(
    scopesRoute: true,
    namesRoute: true,
    explicitChildNodes: true,
    label: label,
    child: const _NotificationCenterPanel(),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion) return FadeTransition(opacity: animation, child: child);
    final curved = CurvedAnimation(
      parent: animation,
      curve: FinanceSuitMenu.openCurve,
      reverseCurve: FinanceSuitMenu.closeCurve,
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, panel) {
        final progress = curved.value.clamp(0.0, 1.0);
        final towardEndEdge = Directionality.of(context) == TextDirection.rtl
            ? -1.0
            : 1.0;
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(
              (1 - progress) * FinanceSuitMenu.entryOffset * towardEndEdge,
              0,
            ),
            child: panel,
          ),
        );
      },
      child: child,
    );
  }
}

class _NotificationCenterPanel extends ConsumerStatefulWidget {
  const _NotificationCenterPanel();

  @override
  ConsumerState<_NotificationCenterPanel> createState() =>
      _NotificationCenterPanelState();
}

class _NotificationCenterPanelState
    extends ConsumerState<_NotificationCenterPanel> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_loadMoreWhenNeeded);
    WidgetsBinding.instance.addPostFrameCallback(
      // Cached pages render immediately; this only refreshes stale content.
      (_) => ref.read(notificationFeedProvider.notifier).loadInitial(),
    );
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadMoreWhenNeeded)
      ..dispose();
    super.dispose();
  }

  void _loadMoreWhenNeeded() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter > 160) return;
    // The controller ignores re-entrant calls, so crossing the threshold
    // repeatedly cannot issue a second request or start a fetch loop.
    unawaited(ref.read(notificationFeedProvider.notifier).loadMore());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.suitColors;
    final l10n = AppLocalizations.of(context);
    final feed = ref.watch(notificationFeedProvider);
    final unread = ref.watch(notificationUnreadCountProvider);
    final foreground = colors.onBrandSurface;
    final mutedForeground = foreground.withValues(alpha: 0.76);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: FractionallySizedBox(
        widthFactor: FinanceSuitMenu.panelWidthFraction,
        heightFactor: 1,
        child: Material(
          key: const Key('notification-center-panel'),
          // Keep the page-plane surface visible; notification content uses
          // the overlay foreground roles for readable contrast.
          type: MaterialType.transparency,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.setNotificationsSection,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      if (feed.refreshing)
                        Padding(
                          key: const Key('notification-center-refreshing'),
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: mutedForeground,
                            ),
                          ),
                        ),
                      IconButton(
                        key: const Key('notification-center-settings'),
                        tooltip: l10n.tabSettings,
                        color: foreground,
                        onPressed: () async {
                          final router = GoRouter.of(context);
                          await NotificationCenter.close();
                          unawaited(router.push(AppRoutes.settings));
                        },
                        icon: const FinanceSuitIcon(FinanceSuitIcons.settings),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _NotificationList(
                    feed: feed,
                    controller: _scrollController,
                    foreground: foreground,
                    mutedForeground: mutedForeground,
                  ),
                ),
                SafeArea(
                  top: false,
                  child: TextButton.icon(
                    key: const Key('notification-center-mark-all-read'),
                    // Driven by the authoritative unread count, so it stays
                    // enabled for unread notifications on pages not loaded.
                    onPressed:
                        unread > 0 || feed.items.any((item) => item.isUnread)
                        ? () => ref
                              .read(notificationFeedProvider.notifier)
                              .markAllRead()
                        : null,
                    icon: const FinanceSuitIcon(FinanceSuitIcons.checkCircle),
                    label: Text(l10n.notificationMarkAllRead),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.primary,
                      disabledForegroundColor: mutedForeground.withValues(
                        alpha: 0.48,
                      ),
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationList extends ConsumerWidget {
  const _NotificationList({
    required this.feed,
    required this.controller,
    required this.foreground,
    required this.mutedForeground,
  });

  final NotificationFeedState feed;
  final ScrollController controller;
  final Color foreground;
  final Color mutedForeground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (feed.loading && feed.items.isEmpty) {
      return _NotificationSkeletonList(mutedForeground: mutedForeground);
    }
    if (feed.error != null && feed.items.isEmpty) {
      return Center(
        key: const Key('notification-center-error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                l10n.notificationLoadFailed,
                textAlign: TextAlign.center,
                style: TextStyle(color: mutedForeground),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('notification-center-retry'),
              onPressed: () => ref
                  .read(notificationFeedProvider.notifier)
                  .loadInitial(force: true),
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      );
    }
    if (feed.items.isEmpty) {
      return Center(
        child: Text(
          l10n.notificationEmpty,
          style: TextStyle(color: mutedForeground),
        ),
      );
    }
    final entries = _groupedEntries(context, feed.items);
    // Only the rendered slice is built, so a user with thousands of
    // historical notifications scrolls at the same cost as one with twenty.
    return ListView.builder(
      key: const Key('notification-center-list'),
      controller: controller,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 12),
      itemCount: entries.length + (feed.loadingMore || !feed.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == entries.length) {
          if (feed.loadingMore) {
            return const Padding(
              key: Key('notification-center-loading-more'),
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return Padding(
            key: const Key('notification-center-end'),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                l10n.notificationEndOfList,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: mutedForeground.withValues(alpha: 0.7),
                ),
              ),
            ),
          );
        }
        final entry = entries[index];
        return switch (entry) {
          _NotificationGroupHeading(:final label) => Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 14, 8, 6),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: mutedForeground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _NotificationGroupItem(:final item) => _NotificationTile(
            item: item,
            foreground: foreground,
            mutedForeground: mutedForeground,
          ),
        };
      },
    );
  }

  List<_NotificationListEntry> _groupedEntries(
    BuildContext context,
    List<NotificationHistoryItem> items,
  ) {
    final l10n = AppLocalizations.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    String groupFor(DateTime value) {
      final date = DateUtils.dateOnly(value);
      final days = today.difference(date).inDays;
      if (days <= 0) return l10n.commonToday;
      if (days == 1) return l10n.notificationYesterday;
      if (days < 7) return l10n.notificationThisWeek;
      return l10n.notificationEarlier;
    }

    final entries = <_NotificationListEntry>[];
    String? previous;
    for (final item in items) {
      final group = groupFor(item.createdAt);
      if (group != previous) {
        entries.add(_NotificationGroupHeading(group));
        previous = group;
      }
      entries.add(_NotificationGroupItem(item));
    }
    return entries;
  }
}

/// Shaped like the real rows so the first paint does not jump, and so the
/// drawer never becomes an indefinite full-panel spinner.
class _NotificationSkeletonList extends StatelessWidget {
  const _NotificationSkeletonList({required this.mutedForeground});

  final Color mutedForeground;

  @override
  Widget build(BuildContext context) {
    final base = mutedForeground.withValues(alpha: 0.12);
    return ListView.builder(
      key: const Key('notification-center-skeleton'),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 12),
      itemCount: 6,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 10, 6, 10),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const SizedBox.square(dimension: 40),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonBar(color: base, widthFactor: 0.6),
                  const SizedBox(height: 6),
                  _SkeletonBar(color: base, widthFactor: 0.85),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.color, required this.widthFactor});

  final Color color;
  final double widthFactor;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    alignment: AlignmentDirectional.centerStart,
    widthFactor: widthFactor,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const SizedBox(height: 10, width: double.infinity),
    ),
  );
}

sealed class _NotificationListEntry {
  const _NotificationListEntry();
}

class _NotificationGroupHeading extends _NotificationListEntry {
  const _NotificationGroupHeading(this.label);
  final String label;
}

class _NotificationGroupItem extends _NotificationListEntry {
  const _NotificationGroupItem(this.item);
  final NotificationHistoryItem item;
}

/// Localized presentation for one event. Machine event keys never reach the
/// user: an event this build does not know renders as a generic entry.
@immutable
class NotificationPresentation {
  const NotificationPresentation({
    required this.title,
    required this.body,
    required this.glyph,
    required this.accent,
  });

  final String title;
  final String body;
  final FinanceSuitGlyph glyph;
  final Color accent;
}

NotificationPresentation notificationPresentation(
  BuildContext context,
  NotificationHistoryItem item,
) {
  final l10n = AppLocalizations.of(context);
  final colors = context.suitColors;
  final locale = Localizations.localeOf(context).toString();
  final account = item.accountName ?? l10n.notificationUnknownAccount;
  final person = item.counterpartyName ?? l10n.notificationUnknownPerson;
  final dueOn = item.dueOn;
  final dueText = dueOn == null
      ? ''
      : DateFormat.MMMd(locale).format(DateTime.parse(dueOn));

  return switch (item.event) {
    NotificationEvent.creditCardStatementDueSoon => NotificationPresentation(
      title: l10n.notifEventCreditCardDueSoon,
      body: l10n.notifBodyAccountDue(account, dueText),
      glyph: FinanceSuitIcons.calendarToday,
      accent: colors.warning.icon,
    ),
    NotificationEvent.creditCardStatementDueToday => NotificationPresentation(
      title: l10n.notifEventCreditCardDueToday,
      body: l10n.notifBodyAccountDue(account, dueText),
      glyph: FinanceSuitIcons.calendarToday,
      accent: colors.warning.icon,
    ),
    NotificationEvent.creditCardStatementOverdue => NotificationPresentation(
      title: l10n.notifEventCreditCardOverdue,
      body: l10n.notifBodyAccountOverdue(account, dueText),
      glyph: FinanceSuitIcons.warning,
      accent: colors.error.icon,
    ),
    NotificationEvent.installmentDueSoon => NotificationPresentation(
      title: l10n.notifEventInstallmentDueSoon,
      body: l10n.notifBodyAccountDue(account, dueText),
      glyph: FinanceSuitIcons.calendarToday,
      accent: colors.warning.icon,
    ),
    NotificationEvent.installmentDueToday => NotificationPresentation(
      title: l10n.notifEventInstallmentDueToday,
      body: l10n.notifBodyAccountDue(account, dueText),
      glyph: FinanceSuitIcons.calendarToday,
      accent: colors.warning.icon,
    ),
    NotificationEvent.installmentOverdue => NotificationPresentation(
      title: l10n.notifEventInstallmentOverdue,
      body: l10n.notifBodyAccountOverdue(account, dueText),
      glyph: FinanceSuitIcons.warning,
      accent: colors.error.icon,
    ),
    NotificationEvent.bnplDueSoon => NotificationPresentation(
      title: l10n.notifEventBnplDueSoon,
      body: l10n.notifBodyAccountDue(account, dueText),
      glyph: FinanceSuitIcons.calendarToday,
      accent: colors.warning.icon,
    ),
    NotificationEvent.bnplDueToday => NotificationPresentation(
      title: l10n.notifEventBnplDueToday,
      body: l10n.notifBodyAccountDue(account, dueText),
      glyph: FinanceSuitIcons.calendarToday,
      accent: colors.warning.icon,
    ),
    NotificationEvent.bnplOverdue => NotificationPresentation(
      title: l10n.notifEventBnplOverdue,
      body: l10n.notifBodyAccountOverdue(account, dueText),
      glyph: FinanceSuitIcons.warning,
      accent: colors.error.icon,
    ),
    NotificationEvent.facilityPaymentRecorded => NotificationPresentation(
      title: l10n.notifEventPaymentRecorded,
      body: l10n.notifBodyAccountPayment(account),
      glyph: FinanceSuitIcons.checkCircle,
      accent: colors.success.icon,
    ),
    NotificationEvent.networkAddRequestReceived => NotificationPresentation(
      title: l10n.notifEventNetworkAddRequest,
      body: l10n.notifBodyPersonAddRequest(person),
      glyph: FinanceSuitIcons.personAdd,
      accent: colors.info.icon,
    ),
    NotificationEvent.networkAddRequestAccepted => NotificationPresentation(
      title: l10n.notifEventNetworkAddAccepted,
      body: l10n.notifBodyPersonAddAccepted(person),
      glyph: FinanceSuitIcons.person,
      accent: colors.success.icon,
    ),
    NotificationEvent.networkTransferReceived => NotificationPresentation(
      title: l10n.notifEventTransferReceived,
      body: l10n.notifBodyPersonTransferReceived(person),
      glyph: FinanceSuitIcons.swapHoriz,
      accent: colors.info.icon,
    ),
    NotificationEvent.networkTransferAccepted => NotificationPresentation(
      title: l10n.notifEventTransferAccepted,
      body: l10n.notifBodyPersonTransferAccepted(person),
      glyph: FinanceSuitIcons.checkCircle,
      accent: colors.success.icon,
    ),
    NotificationEvent.networkTransferDeclined => NotificationPresentation(
      title: l10n.notifEventTransferDeclined,
      body: l10n.notifBodyPersonTransferDeclined(person),
      glyph: FinanceSuitIcons.warning,
      accent: colors.error.icon,
    ),
    NotificationEvent.installmentLinkRequestReceived =>
      NotificationPresentation(
        title: l10n.notifEventLinkRequest,
        body: l10n.notifBodyPersonLinkRequest(person),
        glyph: FinanceSuitIcons.link,
        accent: colors.info.icon,
      ),
    NotificationEvent.installmentLinkAccepted => NotificationPresentation(
      title: l10n.notifEventLinkAccepted,
      body: l10n.notifBodyPersonLinkAccepted(person),
      glyph: FinanceSuitIcons.checkCircle,
      accent: colors.success.icon,
    ),
    NotificationEvent.installmentLinkDeclined => NotificationPresentation(
      title: l10n.notifEventLinkDeclined,
      body: l10n.notifBodyPersonLinkDeclined(person),
      glyph: FinanceSuitIcons.warning,
      accent: colors.error.icon,
    ),
    NotificationEvent.developerTest => NotificationPresentation(
      title: l10n.notifEventDeveloperTest,
      body: l10n.notifBodyDeveloperTest,
      glyph: FinanceSuitIcons.notifications,
      accent: colors.info.icon,
    ),
    NotificationEvent.unknown => NotificationPresentation(
      title: l10n.setNotificationsSection,
      body: l10n.notificationGenericBody,
      glyph: FinanceSuitIcons.notifications,
      accent: colors.info.icon,
    ),
  };
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({
    required this.item,
    required this.foreground,
    required this.mutedForeground,
  });
  final NotificationHistoryItem item;
  final Color foreground;
  final Color mutedForeground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.suitColors;
    final presentation = notificationPresentation(context, item);
    final destination = item.destination;
    final amount = item.amount;
    final locale = Localizations.localeOf(context).toString();
    final timestamp =
        '${DateFormat.MMMd(locale).format(item.createdAt)} · '
        '${DateFormat.jm(locale).format(item.createdAt)}';
    return InkWell(
      key: Key('notification-item-${item.id}'),
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        await ref.read(notificationFeedProvider.notifier).markRead(item.id);
        if (!context.mounted) return;
        if (destination == null) return;
        final router = GoRouter.of(context);
        await NotificationCenter.close();
        // The destination is a validated app route; the screen behind it
        // still loads the entity through the normal repositories under RLS.
        unawaited(router.push(destination));
      },
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: presentation.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SizedBox.square(
                dimension: 40,
                child: FinanceSuitIcon(
                  presentation.glyph,
                  size: 21,
                  color: presentation.accent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    presentation.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (presentation.body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      presentation.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: mutedForeground),
                    ),
                  ],
                  if (amount != null) ...[
                    const SizedBox(height: 4),
                    // Reuses the app's money-privacy control, so amounts in
                    // the Center follow the same reveal rules as everywhere
                    // else instead of a second privacy system.
                    AppMoneyText(
                      money: amount,
                      sign: AppMoneySign.never,
                      style: Theme.of(context).textTheme.labelLarge,
                      color: foreground,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    timestamp,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: mutedForeground.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 16,
              height: 40,
              child: item.isUnread
                  ? Center(
                      child: Semantics(
                        label: l10n.notificationUnreadLabel,
                        child: DecoratedBox(
                          key: Key('notification-unread-${item.id}'),
                          decoration: BoxDecoration(
                            color: colors.info.icon,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(dimension: 7),
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
