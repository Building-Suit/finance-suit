import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/routing/finance_suit_menu.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/notifications/notifications_repository.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

typedef NotificationHistoryLoader =
    Future<Result<NotificationHistoryPage>> Function({
      NotificationHistoryCursor? after,
      int limit,
    });
typedef NotificationReadMutation = Future<Result<void>> Function(String id);
typedef NotificationReadAllMutation = Future<Result<void>> Function();

final notificationHistoryLoaderProvider = Provider<NotificationHistoryLoader>(
  (ref) => ref.watch(notificationsRepositoryProvider).fetchHistory,
);
final notificationReadMutationProvider = Provider<NotificationReadMutation>(
  (ref) => ref.watch(notificationsRepositoryProvider).markHistoryRead,
);
final notificationReadAllMutationProvider =
    Provider<NotificationReadAllMutation>(
      (ref) => ref.watch(notificationsRepositoryProvider).markAllHistoryRead,
    );

@immutable
class NotificationFeedState {
  const NotificationFeedState({
    this.items = const [],
    this.next,
    this.loading = false,
    this.loadingMore = false,
    this.error,
  });

  final List<NotificationHistoryItem> items;
  final NotificationHistoryCursor? next;
  final bool loading;
  final bool loadingMore;
  final Object? error;

  bool get hasMore => next != null;

  NotificationFeedState copyWith({
    List<NotificationHistoryItem>? items,
    NotificationHistoryCursor? next,
    bool clearNext = false,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
  }) => NotificationFeedState(
    items: items ?? this.items,
    next: clearNext ? null : (next ?? this.next),
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: clearError ? null : (error ?? this.error),
  );
}

final notificationFeedProvider =
    NotifierProvider<NotificationFeedController, NotificationFeedState>(
      NotificationFeedController.new,
    );

class NotificationFeedController extends Notifier<NotificationFeedState> {
  @override
  NotificationFeedState build() => const NotificationFeedState();

  Future<void> loadInitial({bool refresh = false}) async {
    if (state.loading || (!refresh && state.items.isNotEmpty)) return;
    state = state.copyWith(loading: true, clearError: true);
    final result = await ref.read(notificationHistoryLoaderProvider)();
    result.when(
      ok: (page) => state = NotificationFeedState(
        items: _deduplicate(page.items),
        next: page.next,
      ),
      err: (failure) => state = state.copyWith(loading: false, error: failure),
    );
  }

  Future<void> loadMore() async {
    final cursor = state.next;
    if (cursor == null || state.loading || state.loadingMore) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    final result = await ref.read(notificationHistoryLoaderProvider)(
      after: cursor,
    );
    result.when(
      ok: (page) => state = NotificationFeedState(
        items: _deduplicate([...state.items, ...page.items]),
        next: page.next,
      ),
      err: (failure) =>
          state = state.copyWith(loadingMore: false, error: failure),
    );
  }

  Future<void> markRead(String id) async {
    final item = state.items.where((entry) => entry.id == id).firstOrNull;
    if (item == null || !item.isUnread) return;
    final readAt = DateTime.now();
    state = state.copyWith(
      items: [
        for (final entry in state.items)
          if (entry.id == id) entry.copyWith(readAt: readAt) else entry,
      ],
    );
    final result = await ref.read(notificationReadMutationProvider)(id);
    result.when(
      ok: (_) {},
      err: (failure) => state = state.copyWith(
        items: [
          for (final entry in state.items)
            if (entry.id == id) item else entry,
        ],
        error: failure,
      ),
    );
  }

  Future<void> markAllRead() async {
    final unread = {
      for (final item in state.items.where((i) => i.isUnread)) item.id,
    };
    if (unread.isEmpty) return;
    final previous = state.items;
    final readAt = DateTime.now();
    state = state.copyWith(
      items: [
        for (final item in previous)
          if (item.isUnread) item.copyWith(readAt: readAt) else item,
      ],
    );
    final result = await ref.read(notificationReadAllMutationProvider)();
    result.when(
      ok: (_) {},
      err: (failure) => state = state.copyWith(items: previous, error: failure),
    );
  }

  static List<NotificationHistoryItem> _deduplicate(
    List<NotificationHistoryItem> source,
  ) {
    final seen = <String>{};
    return source.where((item) => seen.add(item.id)).toList(growable: false);
  }
}

/// Logical-end counterpart to [FinanceSuitMenu]. It reuses the menu's motion,
/// scrim, width and focus semantics while presenting the user's own delivered
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
    if (_scrollController.position.extentAfter > 160) return;
    unawaited(ref.read(notificationFeedProvider.notifier).loadMore());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.suitColors;
    final l10n = AppLocalizations.of(context);
    final feed = ref.watch(notificationFeedProvider);
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
                    onPressed: feed.items.any((item) => item.isUnread)
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
      return Center(
        child: CircularProgressIndicator(color: context.suitColors.info.icon),
      );
    }
    if (feed.error != null && feed.items.isEmpty) {
      return Center(
        child: TextButton(
          onPressed: () => ref
              .read(notificationFeedProvider.notifier)
              .loadInitial(refresh: true),
          child: Text(l10n.commonRetry),
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
    return ListView.builder(
      key: const Key('notification-center-list'),
      controller: controller,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 12),
      itemCount: entries.length + (feed.loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == entries.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
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
    final payload = item.payload;
    final accountName = payload['account_name'] as String?;
    final amount = payload['amount_text'] as String?;
    final (
      title,
      body,
      destination,
      glyph,
      accent,
    ) = switch (item.reminderKind) {
      'overdue' => (
        l10n.dueStatusOverdue,
        accountName ?? l10n.setNotificationsSection,
        AppRoutes.money,
        FinanceSuitIcons.warning,
        colors.error.icon,
      ),
      'payment_confirmation' || 'payment_success' => (
        l10n.paymentTitle,
        [amount, accountName].whereType<String>().join(' · '),
        AppRoutes.money,
        FinanceSuitIcons.checkCircle,
        colors.success.icon,
      ),
      'due_today' || 'due_soon' || 'due_tomorrow' => (
        l10n.dueStatusDueToday,
        [amount, accountName].whereType<String>().join(' · '),
        AppRoutes.money,
        FinanceSuitIcons.calendarToday,
        colors.warning.icon,
      ),
      'plan_completed' => (
        l10n.setNotificationsSection,
        accountName ?? l10n.commonDone,
        AppRoutes.money,
        FinanceSuitIcons.celebration,
        colors.info.icon,
      ),
      _ => (
        l10n.setNotificationsSection,
        accountName ?? l10n.commonToday,
        null,
        FinanceSuitIcons.notifications,
        colors.info.icon,
      ),
    };
    final locale = Localizations.localeOf(context).toString();
    final timestamp =
        '${DateFormat.MMMd(locale).format(item.createdAt)} · '
        '${DateFormat.jm(locale).format(item.createdAt)}';
    return InkWell(
      key: Key('notification-item-${item.id}'),
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        await ref.read(notificationFeedProvider.notifier).markRead(item.id);
        if (!context.mounted || destination == null) return;
        final router = GoRouter.of(context);
        await NotificationCenter.close();
        unawaited(router.push(destination));
      },
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SizedBox.square(
                dimension: 40,
                child: FinanceSuitIcon(glyph, size: 21, color: accent),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: mutedForeground),
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
                      child: DecoratedBox(
                        key: Key('notification-unread-${item.id}'),
                        decoration: BoxDecoration(
                          color: colors.info.icon,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox.square(dimension: 7),
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
