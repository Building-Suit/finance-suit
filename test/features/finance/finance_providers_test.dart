import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';

class _TestUserIdNotifier extends Notifier<String?> {
  @override
  String? build() => 'user-a';

  void setUser(String? userId) => state = userId;
}

final _testUserIdProvider = NotifierProvider<_TestUserIdNotifier, String?>(
  _TestUserIdNotifier.new,
);

class _MockFinanceRepository extends Mock implements FinanceRepository {}

AccountBalance _balance(String id, int minor) => AccountBalance(
  accountId: id,
  name: 'Current Balance',
  accountType: AccountType.current,
  currencyCode: 'EGP',
  isDefault: true,
  isArchived: false,
  allowNegativeBalance: false,
  openingBalanceMinor: minor,
  balanceMinor: minor,
  totalIncomingMinor: 0,
  totalOutgoingMinor: 0,
);

void main() {
  test('account balances refetch when the signed-in user changes', () async {
    final repository = _MockFinanceRepository();
    var calls = 0;
    when(() => repository.fetchAccountBalances()).thenAnswer((_) async {
      calls += 1;
      return Ok([
        calls == 1 ? _balance('account-a', 1000) : _balance('account-b', 2000),
      ]);
    });

    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWith(
          (ref) => ref.watch(_testUserIdProvider),
        ),
        financeRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final first = await container.read(accountBalancesProvider.future);
    expect(first.single.accountId, 'account-a');
    expect(first.single.balanceMinor, 1000);

    container.read(_testUserIdProvider.notifier).setUser('user-b');
    await Future<void>.delayed(Duration.zero);

    final second = await container.read(accountBalancesProvider.future);
    expect(second.single.accountId, 'account-b');
    expect(second.single.balanceMinor, 2000);
    verify(() => repository.fetchAccountBalances()).called(2);
  });
}
