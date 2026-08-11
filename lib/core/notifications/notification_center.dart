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

final notificationHistoryLoaderProvider = Provider<NotificationHistoryLoader>(
  (ref) => ref.watch(notificationsRepositoryProvider).fetchHistory,
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

  static List<NotificationHistoryItem> _deduplicate(
    List<NotificationHistoryItem> source,
  ) {
    final seen = <String>{};
    return source.where((item) => seen.add(item.id)).toList(growable: false);
  }
}

/// Right-side counterpart to [FinanceSuitMenu]. It reuses the menu's motion,
/// scrim, width and focus semantics while presenting the user's own delivered
/// notification history.
abstract final class NotificationCenter {
  static _NotificationCenterRoute? _activeRoute;
  static bool get isOpen => _activeRoute != null;

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
        final towardEnd = Directionality.of(context) == TextDirection.rtl
            ? -1.0
            : 1.0;
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(
              (1 - progress) * FinanceSuitMenu.entryOffset * towardEnd,
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
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: FractionallySizedBox(
        widthFactor: FinanceSuitMenu.panelWidthFraction,
        heightFactor: 1,
        child: Material(
          key: const Key('notification-center-panel'),
          color: colors.surface,
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
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        key: const Key('notification-center-close'),
                        tooltip: l10n.commonClose,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const FinanceSuitIcon(FinanceSuitIcons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _NotificationList(
                    feed: feed,
                    controller: _scrollController,
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
  const _NotificationList({required this.feed, required this.controller});

  final NotificationFeedState feed;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (feed.loading && feed.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
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
    if (feed.items.isEmpty) return Center(child: Text(l10n.commonEmpty));
    return ListView.builder(
      key: const Key('notification-center-list'),
      controller: controller,
      itemCount: feed.items.length + (feed.loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == feed.items.length) {
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
        return _NotificationTile(item: feed.items[index]);
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});
  final NotificationHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (title, body, destination) = switch (item.reminderKind) {
      'overdue' => (
        l10n.dueStatusOverdue,
        l10n.setNotificationsSection,
        AppRoutes.money,
      ),
      'payment_confirmation' || 'payment_success' => (
        l10n.paymentTitle,
        l10n.setNotificationsSection,
        AppRoutes.money,
      ),
      'due_today' => (
        l10n.dueStatusDueToday,
        l10n.setNotificationsSection,
        AppRoutes.money,
      ),
      _ => (l10n.setNotificationsSection, l10n.commonToday, null),
    };
    return ListTile(
      key: Key('notification-item-${item.id}'),
      leading: const FinanceSuitIcon(FinanceSuitIcons.notifications),
      title: Text(title),
      subtitle: Text(
        '$body · ${DateFormat.yMMMd(Localizations.localeOf(context).toString()).add_jm().format(item.createdAt)}',
      ),
      onTap: destination == null
          ? null
          : () {
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              unawaited(router.push(destination));
            },
    );
  }
}
