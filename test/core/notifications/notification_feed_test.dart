import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/notifications/notification_events.dart';
import 'package:work_tracker/core/notifications/notification_feed.dart';
import 'package:work_tracker/core/notifications/notifications_repository.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';

final _base = DateTime.utc(2026, 8, 17, 12);

NotificationHistoryItem notification(int index, {DateTime? readAt}) =>
    NotificationHistoryItem(
      id: 'n${index.toString().padLeft(3, '0')}',
      event: NotificationEvent.installmentDueToday,
      createdAt: _base.subtract(Duration(minutes: index)),
      readAt: readAt,
      payload: const {'account_name': 'Card'},
    );

/// A paged server: `total` notifications served newest-first through the same
/// keyset contract the repository uses.
class FakeHistoryServer {
  FakeHistoryServer(int total)
    : all = List.generate(total, notification),
      calls = [];

  final List<NotificationHistoryItem> all;
  final List<NotificationHistoryCursor?> calls;
  int requests = 0;

  Future<Result<NotificationHistoryPage>> load({
    NotificationHistoryCursor? after,
    int limit = kNotificationPageSize,
  }) async {
    requests++;
    calls.add(after);
    final start = after == null
        ? 0
        : all.indexWhere((item) => item.id == after.id) + 1;
    final slice = all.skip(start).take(limit).toList();
    final consumed = start + slice.length;
    return Ok(
      NotificationHistoryPage(
        items: slice,
        next: consumed >= all.length || slice.isEmpty
            ? null
            : NotificationHistoryCursor(
                createdAt: slice.last.createdAt,
                id: slice.last.id,
              ),
      ),
    );
  }
}

ProviderContainer makeContainer({
  required FakeHistoryServer server,
  String? userId = 'user-a',
  Future<Result<int>> Function({List<String>? ids})? read,
  Future<Result<int>> Function()? unread,
  NotificationFeedCache? cache,
}) {
  final container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue(userId),
      notificationHistoryLoaderProvider.overrideWithValue(server.load),
      notificationReadMutationProvider.overrideWithValue(
        read ?? ({List<String>? ids}) async => const Ok(0),
      ),
      notificationUnreadReaderProvider.overrideWithValue(
        unread ?? () async => const Ok(0),
      ),
      if (cache != null) notificationFeedCacheProvider.overrideWithValue(cache),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('pagination', () {
    test('the first network fetch asks for at most 20 notifications', () async {
      final server = FakeHistoryServer(100);
      final container = makeContainer(server: server);
      await container.read(notificationFeedProvider.notifier).loadInitial();

      expect(server.requests, 1);
      expect(server.calls.single, isNull);
      expect(container.read(notificationFeedProvider).items, hasLength(20));
      expect(container.read(notificationFeedProvider).hasMore, isTrue);
    });

    test('paging walks the whole history without gaps or duplicates', () async {
      final server = FakeHistoryServer(45);
      final container = makeContainer(server: server);
      final controller = container.read(notificationFeedProvider.notifier);
      await controller.loadInitial();
      while (container.read(notificationFeedProvider).hasMore) {
        await controller.loadMore();
      }

      final items = container.read(notificationFeedProvider).items;
      expect(items, hasLength(45));
      expect(items.map((item) => item.id).toSet(), hasLength(45));
      expect(items.map((item) => item.id), server.all.map((item) => item.id));
    });

    test('only one next-page fetch runs at a time', () async {
      final server = FakeHistoryServer(100);
      final container = makeContainer(server: server);
      final controller = container.read(notificationFeedProvider.notifier);
      await controller.loadInitial();
      expect(server.requests, 1);

      // The infinite-scroll threshold fires on every scroll frame; repeated
      // calls must not stack requests.
      await Future.wait([
        controller.loadMore(),
        controller.loadMore(),
        controller.loadMore(),
      ]);
      expect(server.requests, 2);
      expect(container.read(notificationFeedProvider).items, hasLength(40));
    });

    test('reaching the end stops further requests', () async {
      final server = FakeHistoryServer(15);
      final container = makeContainer(server: server);
      final controller = container.read(notificationFeedProvider.notifier);
      await controller.loadInitial();

      expect(container.read(notificationFeedProvider).hasMore, isFalse);
      await controller.loadMore();
      await controller.loadMore();
      expect(server.requests, 1);
    });
  });

  group('cache', () {
    test('reopening serves cached pages without discarding them', () async {
      final cache = NotificationFeedCache();
      final server = FakeHistoryServer(100);
      var container = makeContainer(server: server, cache: cache);
      final controller = container.read(notificationFeedProvider.notifier);
      await controller.loadInitial();
      await controller.loadMore();
      expect(container.read(notificationFeedProvider).items, hasLength(40));
      container.dispose();

      // A new container stands in for closing and reopening the drawer.
      container = makeContainer(server: server, cache: cache);
      final restored = container.read(notificationFeedProvider);
      expect(restored.items, hasLength(40));
      expect(restored.hasMore, isTrue);

      // Fresh cache: no network on reopen.
      await container.read(notificationFeedProvider.notifier).loadInitial();
      expect(server.requests, 2);
    });

    test(
      'a stale cache refreshes in the background, not behind a spinner',
      () async {
        final cache = NotificationFeedCache();
        final server = FakeHistoryServer(100);
        var container = makeContainer(server: server, cache: cache);
        await container.read(notificationFeedProvider.notifier).loadInitial();
        container.dispose();

        cache.fetchedAt = DateTime.now().subtract(const Duration(hours: 1));
        container = makeContainer(server: server, cache: cache);
        // Cached rows are on screen before the refresh resolves.
        expect(container.read(notificationFeedProvider).items, hasLength(20));
        final refresh = container
            .read(notificationFeedProvider.notifier)
            .loadInitial();
        expect(container.read(notificationFeedProvider).loading, isFalse);
        expect(container.read(notificationFeedProvider).refreshing, isTrue);
        await refresh;
        expect(server.requests, 2);
        expect(container.read(notificationFeedProvider).items, hasLength(20));
      },
    );

    test('a refresh keeps pages the user already scrolled to', () async {
      final cache = NotificationFeedCache();
      final server = FakeHistoryServer(100);
      final container = makeContainer(server: server, cache: cache);
      final controller = container.read(notificationFeedProvider.notifier);
      await controller.loadInitial();
      await controller.loadMore();
      await controller.loadMore();
      expect(container.read(notificationFeedProvider).items, hasLength(60));

      await controller.loadInitial(force: true);
      final state = container.read(notificationFeedProvider);
      // The refreshed first page overlaps the cache, so the deeper pages are
      // still there and the cursor still points past them.
      expect(state.items, hasLength(60));
      expect(state.items.map((item) => item.id).toSet(), hasLength(60));
      expect(state.next?.id, 'n059');

      await controller.loadMore();
      expect(container.read(notificationFeedProvider).items, hasLength(80));
    });

    test('a refresh with no overlap drops a cache it cannot trust', () async {
      final cache = NotificationFeedCache();
      final server = FakeHistoryServer(100);
      final container = makeContainer(server: server, cache: cache);
      final controller = container.read(notificationFeedProvider.notifier);
      await controller.loadInitial();
      await controller.loadMore();

      // 40 newer notifications arrived while the drawer was closed, so the
      // fresh first page no longer reaches the cached rows.
      server.all.insertAll(
        0,
        List.generate(
          40,
          (index) => NotificationHistoryItem(
            id: 'new-$index',
            event: NotificationEvent.networkTransferReceived,
            createdAt: _base.add(Duration(minutes: 40 - index)),
            payload: const {},
          ),
        ),
      );

      await controller.loadInitial(force: true);
      final state = container.read(notificationFeedProvider);
      expect(state.items, hasLength(20));
      expect(state.items.first.id, 'new-0');
      // Keeping a disjoint cache would leave a silent hole in the list.
      expect(state.items.map((item) => item.id), isNot(contains('n000')));
    });

    test(
      'signing in as another user never shows the previous history',
      () async {
        final cache = NotificationFeedCache();
        final server = FakeHistoryServer(100);
        var container = makeContainer(server: server, cache: cache);
        await container.read(notificationFeedProvider.notifier).loadInitial();
        expect(container.read(notificationFeedProvider).items, isNotEmpty);
        container.dispose();

        container = makeContainer(
          server: server,
          cache: cache,
          userId: 'user-b',
        );
        expect(container.read(notificationFeedProvider).items, isEmpty);
        expect(cache.items, isEmpty);
      },
    );

    test('signing out clears the cached feed', () async {
      final cache = NotificationFeedCache();
      final server = FakeHistoryServer(100);
      var container = makeContainer(server: server, cache: cache);
      await container.read(notificationFeedProvider.notifier).loadInitial();
      container.dispose();

      container = makeContainer(server: server, cache: cache, userId: null);
      expect(container.read(notificationFeedProvider).items, isEmpty);
    });
  });

  group('realtime', () {
    test('an incoming notification appears once at the top', () async {
      final server = FakeHistoryServer(30);
      final container = makeContainer(server: server);
      final controller = container.read(notificationFeedProvider.notifier);
      await controller.loadInitial();

      final incoming = NotificationHistoryItem(
        id: 'live-1',
        event: NotificationEvent.networkTransferReceived,
        createdAt: _base.add(const Duration(minutes: 5)),
        payload: const {},
      );
      controller
        ..receive(incoming)
        // A reconnect can replay the same row.
        ..receive(incoming);

      final items = container.read(notificationFeedProvider).items;
      expect(items.first.id, 'live-1');
      expect(items.where((item) => item.id == 'live-1'), hasLength(1));
      expect(items, hasLength(21));
    });

    test('a refresh does not drop or duplicate a realtime row', () async {
      final server = FakeHistoryServer(30);
      final container = makeContainer(server: server);
      final controller = container.read(notificationFeedProvider.notifier);
      await controller.loadInitial();
      controller.receive(
        NotificationHistoryItem(
          id: 'live-1',
          event: NotificationEvent.networkTransferReceived,
          createdAt: _base.add(const Duration(minutes: 5)),
          payload: const {},
        ),
      );

      await controller.loadInitial(force: true);
      final items = container.read(notificationFeedProvider).items;
      expect(items.first.id, 'live-1');
      expect(items.map((item) => item.id).toSet(), hasLength(items.length));
    });

    test('a realtime row already in the page is not duplicated', () async {
      final server = FakeHistoryServer(30);
      final container = makeContainer(server: server);
      final controller = container.read(notificationFeedProvider.notifier);
      await controller.loadInitial();

      controller.receive(server.all.first);
      final items = container.read(notificationFeedProvider).items;
      expect(items, hasLength(20));
      expect(items.map((item) => item.id).toSet(), hasLength(20));
    });
  });

  group('read state', () {
    test('marking one read updates the item and the badge', () async {
      final server = FakeHistoryServer(5);
      final container = makeContainer(
        server: server,
        read: ({List<String>? ids}) async => const Ok(4),
      );
      final controller = container.read(notificationFeedProvider.notifier);
      await controller.loadInitial();
      container.read(notificationUnreadCountProvider.notifier).setCount(5);

      await controller.markRead('n000');
      final item = container
          .read(notificationFeedProvider)
          .items
          .firstWhere((entry) => entry.id == 'n000');
      expect(item.isUnread, isFalse);
      expect(container.read(notificationUnreadCountProvider), 4);
    });

    test(
      'a failed mark-read is reverted rather than silently accepted',
      () async {
        final server = FakeHistoryServer(5);
        final container = makeContainer(
          server: server,
          read: ({List<String>? ids}) async => const Err<int>(NetworkFailure()),
          unread: () async => const Ok(5),
        );
        final controller = container.read(notificationFeedProvider.notifier);
        await controller.loadInitial();

        await controller.markRead('n000');
        final state = container.read(notificationFeedProvider);
        expect(
          state.items.firstWhere((entry) => entry.id == 'n000').isUnread,
          isTrue,
        );
        expect(state.error, isNotNull);
      },
    );

    test('mark all read empties the badge in one request', () async {
      final server = FakeHistoryServer(30);
      var calls = 0;
      List<String>? received;
      final container = makeContainer(
        server: server,
        read: ({List<String>? ids}) async {
          calls++;
          received = ids;
          return const Ok(0);
        },
      );
      final controller = container.read(notificationFeedProvider.notifier);
      await controller.loadInitial();
      container.read(notificationUnreadCountProvider.notifier).setCount(30);

      await controller.markAllRead();
      expect(calls, 1);
      // Null means "everything", so unread rows on unloaded pages are
      // cleared too instead of one request per visible row.
      expect(received, isNull);
      expect(
        container
            .read(notificationFeedProvider)
            .items
            .every((item) => !item.isUnread),
        isTrue,
      );
      expect(container.read(notificationUnreadCountProvider), 0);
    });

    test('a failed mark-all restores every previous read state', () async {
      final server = FakeHistoryServer(5);
      final container = makeContainer(
        server: server,
        read: ({List<String>? ids}) async => const Err<int>(NetworkFailure()),
        unread: () async => const Ok(5),
      );
      final controller = container.read(notificationFeedProvider.notifier);
      await controller.loadInitial();

      await controller.markAllRead();
      expect(
        container
            .read(notificationFeedProvider)
            .items
            .every((item) => item.isUnread),
        isTrue,
      );
    });
  });

  group('unread count', () {
    test(
      'reads the authoritative server count, not the loaded pages',
      () async {
        final server = FakeHistoryServer(5);
        final container = makeContainer(
          server: server,
          // Far more unread than the feed has ever loaded.
          unread: () async => const Ok(137),
        );
        await container.read(notificationFeedProvider.notifier).loadInitial();
        await container
            .read(notificationUnreadCountProvider.notifier)
            .refresh();
        expect(container.read(notificationUnreadCountProvider), 137);
      },
    );

    test('a signed-out session reports zero', () async {
      final server = FakeHistoryServer(5);
      final container = makeContainer(
        server: server,
        userId: null,
        unread: () async => const Ok(9),
      );
      expect(container.read(notificationUnreadCountProvider), 0);
      await container.read(notificationUnreadCountProvider.notifier).refresh();
      expect(container.read(notificationUnreadCountProvider), 0);
    });

    test(
      'a failed refresh keeps the last known count, never a negative',
      () async {
        final server = FakeHistoryServer(5);
        final container = makeContainer(
          server: server,
          unread: () async => const Err<int>(NetworkFailure()),
        );
        final controller = container.read(
          notificationUnreadCountProvider.notifier,
        )..setCount(3);
        await controller.refresh();
        expect(container.read(notificationUnreadCountProvider), 3);

        controller.setCount(-5);
        expect(container.read(notificationUnreadCountProvider), 0);
      },
    );
  });
}
