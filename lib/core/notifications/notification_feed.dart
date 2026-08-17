import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/notifications/notifications_repository.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';

/// First network page size. The Notification Center must never pull a user's
/// whole history on open.
const kNotificationPageSize = 20;

/// How long a cached first page is served without a background refresh.
const kNotificationCacheTtl = Duration(minutes: 2);

typedef NotificationHistoryLoader =
    Future<Result<NotificationHistoryPage>> Function({
      NotificationHistoryCursor? after,
      int limit,
    });

/// Marks the given ids read, or everything when null. Resolves to the
/// server's reconciled unread count.
typedef NotificationReadMutation =
    Future<Result<int>> Function({List<String>? ids});

typedef NotificationUnreadReader = Future<Result<int>> Function();

final notificationHistoryLoaderProvider = Provider<NotificationHistoryLoader>(
  (ref) => ref.watch(notificationsRepositoryProvider).fetchHistory,
);
final notificationReadMutationProvider = Provider<NotificationReadMutation>(
  (ref) => ref.watch(notificationsRepositoryProvider).markRead,
);
final notificationUnreadReaderProvider = Provider<NotificationUnreadReader>(
  (ref) => ref.watch(notificationsRepositoryProvider).unreadCount,
);

/// Survives closing the drawer so reopening shows content immediately, and is
/// keyed by user so signing in as somebody else can never show the previous
/// account's notifications.
class NotificationFeedCache {
  String? userId;
  List<NotificationHistoryItem> items = const [];
  NotificationHistoryCursor? next;
  DateTime? fetchedAt;

  bool get isEmpty => items.isEmpty;

  bool isStale(DateTime now) {
    final at = fetchedAt;
    return at == null || now.difference(at) > kNotificationCacheTtl;
  }

  void clear() {
    userId = null;
    items = const [];
    next = null;
    fetchedAt = null;
  }

  void save({
    required String? userId,
    required List<NotificationHistoryItem> items,
    required NotificationHistoryCursor? next,
    required DateTime fetchedAt,
  }) {
    this.userId = userId;
    this.items = items;
    this.next = next;
    this.fetchedAt = fetchedAt;
  }
}

final notificationFeedCacheProvider = Provider<NotificationFeedCache>(
  (ref) => NotificationFeedCache(),
);

/// The signed-in user, or null when no Supabase client is available.
///
/// The header bell is shared chrome: it also renders in isolated previews and
/// plain Material test harnesses that never initialise Supabase. Reading
/// identity there must degrade to "signed out" rather than take the whole
/// header down, exactly as the app bar already does for its theme extension.
String? _signedInUserId(Ref ref, {bool watch = true}) {
  try {
    return watch
        ? ref.watch(currentUserIdProvider)
        : ref.read(currentUserIdProvider);
  } on Object {
    return null;
  }
}

@immutable
class NotificationFeedState {
  const NotificationFeedState({
    this.items = const [],
    this.next,
    this.loading = false,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
  });

  final List<NotificationHistoryItem> items;
  final NotificationHistoryCursor? next;

  /// A first load with nothing to show yet: the drawer renders skeleton rows.
  final bool loading;

  /// Cached content is on screen while a fresher first page is fetched.
  final bool refreshing;
  final bool loadingMore;
  final Object? error;

  bool get hasMore => next != null;
  bool get isEmpty => items.isEmpty && !loading;

  NotificationFeedState copyWith({
    List<NotificationHistoryItem>? items,
    NotificationHistoryCursor? next,
    bool clearNext = false,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
  }) => NotificationFeedState(
    items: items ?? this.items,
    next: clearNext ? null : (next ?? this.next),
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    loadingMore: loadingMore ?? this.loadingMore,
    error: clearError ? null : (error ?? this.error),
  );
}

final notificationFeedProvider =
    NotifierProvider<NotificationFeedController, NotificationFeedState>(
      NotificationFeedController.new,
    );

class NotificationFeedController extends Notifier<NotificationFeedState> {
  bool _loadingInitial = false;

  @override
  NotificationFeedState build() {
    final userId = _signedInUserId(ref);
    final cache = ref.read(notificationFeedCacheProvider);
    if (cache.userId != userId) {
      // Sign-out or a different account: previously loaded pages are not
      // this user's to see.
      cache.clear();
      cache.userId = userId;
      return const NotificationFeedState();
    }
    return NotificationFeedState(items: cache.items, next: cache.next);
  }

  /// Serves cached content immediately and refreshes it in the background.
  /// Only a genuinely empty cache shows a loading state.
  Future<void> loadInitial({bool force = false}) async {
    if (_loadingInitial) return;
    final cache = ref.read(notificationFeedCacheProvider);
    final hasCache = state.items.isNotEmpty;
    if (hasCache && !force && !cache.isStale(DateTime.now())) return;

    _loadingInitial = true;
    state = state.copyWith(
      loading: !hasCache,
      refreshing: hasCache,
      clearError: true,
    );
    final result = await ref.read(notificationHistoryLoaderProvider)(
      limit: kNotificationPageSize,
    );
    result.when(
      ok: (page) {
        // A realtime row that arrived while the request was in flight is
        // newer than the page, so keep it rather than letting the refresh
        // drop it.
        final merged = _merge(state.items, page.items);
        state = NotificationFeedState(items: merged, next: page.next);
        _persist();
      },
      err: (failure) => state = state.copyWith(
        loading: false,
        refreshing: false,
        error: failure,
      ),
    );
    _loadingInitial = false;
  }

  /// Requests the next page. Exactly one next-page fetch runs at a time, and
  /// the end of the list stops further requests.
  Future<void> loadMore() async {
    final cursor = state.next;
    if (cursor == null || state.loading || state.loadingMore) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    final result = await ref.read(notificationHistoryLoaderProvider)(
      after: cursor,
      limit: kNotificationPageSize,
    );
    result.when(
      ok: (page) {
        state = NotificationFeedState(
          items: _deduplicate([...state.items, ...page.items]),
          next: page.next,
        );
        _persist();
      },
      err: (failure) =>
          state = state.copyWith(loadingMore: false, error: failure),
    );
  }

  /// Places a realtime notification at the top exactly once. A row already
  /// present (because a refresh raced the subscription) is not duplicated.
  void receive(NotificationHistoryItem item) {
    if (state.items.any((existing) => existing.id == item.id)) return;
    state = state.copyWith(items: [item, ...state.items]);
    _persist();
  }

  Future<void> markRead(String id) async {
    final item = state.items.where((entry) => entry.id == id).firstOrNull;
    if (item == null || !item.isUnread) return;
    final previous = state.items;
    state = state.copyWith(
      items: [
        for (final entry in previous)
          if (entry.id == id) entry.copyWith(readAt: DateTime.now()) else entry,
      ],
    );
    _persist();
    final result = await ref.read(notificationReadMutationProvider)(ids: [id]);
    result.when(
      ok: (unread) =>
          ref.read(notificationUnreadCountProvider.notifier).setCount(unread),
      err: (failure) {
        // Never leave the user believing a failed mutation succeeded.
        state = state.copyWith(items: previous, error: failure);
        _persist();
        ref.read(notificationUnreadCountProvider.notifier).refresh();
      },
    );
  }

  Future<void> markAllRead() async {
    if (!state.items.any((item) => item.isUnread)) return;
    final previous = state.items;
    final readAt = DateTime.now();
    state = state.copyWith(
      items: [
        for (final item in previous)
          if (item.isUnread) item.copyWith(readAt: readAt) else item,
      ],
    );
    _persist();
    final result = await ref.read(notificationReadMutationProvider)();
    result.when(
      ok: (unread) =>
          ref.read(notificationUnreadCountProvider.notifier).setCount(unread),
      err: (failure) {
        state = state.copyWith(items: previous, error: failure);
        _persist();
        ref.read(notificationUnreadCountProvider.notifier).refresh();
      },
    );
  }

  void _persist() {
    ref
        .read(notificationFeedCacheProvider)
        .save(
          userId: _signedInUserId(ref, watch: false),
          items: state.items,
          next: state.next,
          fetchedAt: DateTime.now(),
        );
  }

  /// Keeps newest-first order while removing ids seen in either list.
  static List<NotificationHistoryItem> _merge(
    List<NotificationHistoryItem> existing,
    List<NotificationHistoryItem> incoming,
  ) {
    final incomingIds = {for (final item in incoming) item.id};
    final newer = existing
        .where((item) => !incomingIds.contains(item.id))
        .where(
          (item) =>
              incoming.isEmpty ||
              item.createdAt.isAfter(incoming.first.createdAt),
        );
    return _deduplicate([...newer, ...incoming]);
  }

  static List<NotificationHistoryItem> _deduplicate(
    List<NotificationHistoryItem> source,
  ) {
    final seen = <String>{};
    return source.where((item) => seen.add(item.id)).toList(growable: false);
  }
}

/// The one authoritative unread count for the whole app.
///
/// Header bell, app badge and Notification Center all read this. It is a
/// small server-side count, never derived from how many history pages happen
/// to be loaded.
final notificationUnreadCountProvider =
    NotifierProvider<NotificationUnreadCountController, int>(
      NotificationUnreadCountController.new,
    );

class NotificationUnreadCountController extends Notifier<int> {
  @override
  int build() {
    final userId = _signedInUserId(ref);
    if (userId == null) return 0;
    // Never leaves a stale positive count on screen: a failed read resets to
    // the last known value rather than inventing one.
    unawaited(refresh());
    return 0;
  }

  Future<void> refresh() async {
    if (_signedInUserId(ref, watch: false) == null) {
      state = 0;
      return;
    }
    final NotificationUnreadReader read;
    try {
      read = ref.read(notificationUnreadReaderProvider);
    } on Object {
      // No repository available (isolated preview or bare test harness).
      // The bell simply carries no badge.
      return;
    }
    final result = await read();
    // A failed read keeps the last known count rather than inventing one or
    // leaving a stale positive number that can never clear.
    result.when(ok: (value) => state = value < 0 ? 0 : value, err: (_) {});
  }

  void setCount(int value) => state = value < 0 ? 0 : value;

  void increment() => state = state + 1;
}

/// One subscription for the whole session.
///
/// Watched from the authenticated shell, so it is created once per signed-in
/// user and torn down on sign-out. Navigation, hot reload and resume reuse the
/// same channel instead of stacking callbacks, and the channel name is keyed
/// by user so a previous account's subscription can never survive a switch.
final notificationRealtimeProvider = Provider<void>((ref) {
  final userId = _signedInUserId(ref);
  if (userId == null) return;
  final SupabaseClient client;
  try {
    client = ref.watch(supabaseClientProvider);
  } on Object {
    return;
  }

  final channel = client.channel('notifications-$userId')
    ..onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: AppSchemas.core,
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (payload) {
        final NotificationHistoryItem item;
        try {
          item = NotificationHistoryItem.fromJson(payload.newRecord);
        } on Object {
          // A row shape this build cannot parse must not break the session;
          // the count refresh below still keeps the badge honest.
          ref.read(notificationUnreadCountProvider.notifier).refresh();
          return;
        }
        ref.read(notificationFeedProvider.notifier).receive(item);
        if (item.isUnread) {
          ref.read(notificationUnreadCountProvider.notifier).increment();
        }
      },
    )
    ..onPostgresChanges(
      // Read state can also change on another device.
      event: PostgresChangeEvent.update,
      schema: AppSchemas.core,
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (_) =>
          ref.read(notificationUnreadCountProvider.notifier).refresh(),
    );
  channel.subscribe();

  ref.onDispose(() => unawaited(client.removeChannel(channel)));
});
