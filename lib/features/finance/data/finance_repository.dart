import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';

class FinanceRepository {
  FinanceRepository(this._client);

  final SupabaseClient _client;

  SupabaseQuerySchema get _db => _client.schema(AppSchemas.finance);

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AuthFailure(AuthFailureKind.sessionMissing);
    }
    return id;
  }

  // ---------------------------------------------------------------------
  // Accounts
  // ---------------------------------------------------------------------

  Future<Result<List<AccountBalance>>> fetchAccountBalances({
    bool includeArchived = false,
  }) {
    return guard(() async {
      var query = _db.from('account_balances').select().eq('user_id', _userId);
      if (!includeArchived) {
        query = query.eq('is_archived', false);
      }
      final rows = await query.order('name', ascending: true);
      return rows.map(AccountBalance.fromJson).toList();
    });
  }

  Future<Result<Account>> fetchAccount(String id) {
    return guard(() async {
      final row = await _db.from('accounts').select().eq('id', id).single();
      return Account.fromJson(row);
    });
  }

  Future<Result<void>> createAccount({
    required String name,
    required AccountType accountType,
    required String currencyCode,
    required int openingBalanceMinor,
    required bool allowNegativeBalance,
    String? notes,
  }) {
    return guard(() async {
      await _db.from('accounts').insert({
        'user_id': _userId,
        'name': name,
        'account_type': accountType.dbValue,
        'currency_code': currencyCode,
        'opening_balance_minor': openingBalanceMinor,
        'allow_negative_balance': allowNegativeBalance,
        'notes': notes,
      });
    });
  }

  Future<Result<void>> updateAccount({
    required String id,
    required String name,
    required AccountType accountType,
    required int openingBalanceMinor,
    required bool allowNegativeBalance,
    String? notes,
  }) {
    return guard(() async {
      await _db
          .from('accounts')
          .update({
            'name': name,
            'account_type': accountType.dbValue,
            'opening_balance_minor': openingBalanceMinor,
            'allow_negative_balance': allowNegativeBalance,
            'notes': notes,
          })
          .eq('id', id);
    });
  }

  Future<Result<void>> setArchived(String id, {required bool archived}) {
    return guard(() async {
      // Archiving the default account would leave the user without one;
      // the archived account also loses its default flag.
      final patch = <String, dynamic>{'is_archived': archived};
      if (archived) patch['is_default'] = false;
      await _db.from('accounts').update(patch).eq('id', id);
    });
  }

  Future<Result<void>> setDefaultAccount(String id) {
    return guard(() async {
      // Partial unique index allows one default among active accounts.
      await _db
          .from('accounts')
          .update({'is_default': false})
          .eq('user_id', _userId)
          .eq('is_default', true);
      await _db.from('accounts').update({'is_default': true}).eq('id', id);
    });
  }

  // ---------------------------------------------------------------------
  // Categories
  // ---------------------------------------------------------------------

  Future<Result<List<TransactionCategory>>> fetchCategories({
    CategoryKind? kind,
    bool includeArchived = false,
  }) {
    return guard(() async {
      var query = _db
          .from('transaction_categories')
          .select()
          .eq('user_id', _userId);
      if (kind != null) {
        query = query.eq('category_kind', kind.dbValue);
      }
      if (!includeArchived) {
        query = query.eq('is_archived', false);
      }
      final rows = await query
          .order('sort_order', ascending: true)
          .order('name', ascending: true);
      return rows.map(TransactionCategory.fromJson).toList();
    });
  }

  Future<Result<void>> createCategory({
    required String name,
    required CategoryKind kind,
    String icon = 'category',
  }) {
    return guard(() async {
      await _db.from('transaction_categories').insert({
        'user_id': _userId,
        'name': name,
        'category_kind': kind.dbValue,
        'icon': icon,
      });
    });
  }

  Future<Result<void>> renameCategory(String id, String name) {
    return guard(() async {
      await _db
          .from('transaction_categories')
          .update({'name': name})
          .eq('id', id);
    });
  }

  Future<Result<void>> setCategoryArchived(
    String id, {
    required bool archived,
  }) {
    return guard(() async {
      await _db
          .from('transaction_categories')
          .update({'is_archived': archived})
          .eq('id', id);
    });
  }

  // ---------------------------------------------------------------------
  // Transactions
  // ---------------------------------------------------------------------

  Future<Result<List<FinancialTransaction>>> fetchRecentTransactions({
    int limit = 50,
  }) {
    return guard(() async {
      final rows = await _db
          .from('financial_transactions')
          .select()
          .eq('user_id', _userId)
          .order('occurred_on', ascending: false)
          .order('id', ascending: false)
          .limit(limit);
      return rows.map(FinancialTransaction.fromJson).toList();
    });
  }

  Future<Result<void>> createTransaction(TransactionDraft draft) {
    return guard(() async {
      await _db.from('financial_transactions').insert({
        'user_id': _userId,
        ...draft.toJson(),
      });
    });
  }

  Future<Result<void>> updateTransaction(String id, TransactionDraft draft) {
    return guard(() async {
      await _db
          .from('financial_transactions')
          .update(draft.toJson())
          .eq('id', id);
    });
  }

  Future<Result<void>> deleteTransaction(String id) {
    return guard(() async {
      await _db.from('financial_transactions').delete().eq('id', id);
    });
  }

  /// Atomic same-currency transfer via the database RPC, which validates
  /// ownership, archival state, currency match, and overdraft rules.
  Future<Result<void>> createTransfer({
    required String sourceAccountId,
    required String destinationAccountId,
    required int amountMinor,
    required PlainDate occurredOn,
    String? notes,
  }) {
    return guard(() async {
      await _db.rpc<String>(
        'create_transfer',
        params: {
          'p_source_account_id': sourceAccountId,
          'p_destination_account_id': destinationAccountId,
          'p_amount_minor': amountMinor,
          'p_occurred_on': occurredOn.toIso(),
          'p_notes': notes,
        },
      );
    });
  }
}

final financeRepositoryProvider = Provider<FinanceRepository>(
  (ref) => FinanceRepository(ref.watch(supabaseClientProvider)),
);
