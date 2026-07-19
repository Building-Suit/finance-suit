import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';
import 'package:work_tracker/features/finance/domain/held_amount.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/domain/transaction_macro.dart';

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
      // Business date first, then the explicit display order. Macro runs give
      // each generated row a stable sort_at so authored action order survives
      // their shared transaction timestamp.
      final rows = await _db
          .from('financial_transactions')
          .select()
          .eq('user_id', _userId)
          .order('occurred_on', ascending: false)
          .order('sort_at', ascending: false)
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

  // ---------------------------------------------------------------------
  // Macros
  // ---------------------------------------------------------------------

  Future<Result<List<TransactionMacro>>> fetchMacros() {
    return guard(() async {
      final rows = await _db
          .from('transaction_macros')
          .select('*, transaction_macro_items(*)')
          .eq('user_id', _userId)
          .order('name', ascending: true);
      return rows.map(TransactionMacro.fromJson).toList();
    });
  }

  /// Atomic create/update of a macro and its full item list via the
  /// `save_macro` RPC. Returns the macro id.
  Future<Result<String>> saveMacro({
    required String name,
    required List<TransactionMacroItem> items,
    String? macroId,
  }) {
    return guard(() async {
      return _db.rpc<String>(
        'save_macro',
        params: {
          'p_name': name,
          'p_items': [
            for (final (position, item) in items.indexed)
              item.toPayload(position),
          ],
          'p_macro_id': macroId,
        },
      );
    });
  }

  Future<Result<void>> deleteMacro(String id) {
    return guard(() async {
      await _db.from('transaction_macros').delete().eq('id', id);
    });
  }

  /// Applies a macro atomically via the `apply_macro` RPC and returns the
  /// number of transactions created. Reverse runs apply only reversible
  /// items and swap transfer directions.
  Future<Result<int>> applyMacro({
    required String macroId,
    required PlainDate occurredOn,
    bool reverse = false,
  }) {
    return guard(() async {
      final ids = await _db.rpc<List<dynamic>>(
        'apply_macro',
        params: {
          'p_macro_id': macroId,
          'p_occurred_on': occurredOn.toIso(),
          'p_reverse': reverse,
        },
      );
      return ids.length;
    });
  }

  // ---------------------------------------------------------------------
  // Held amounts
  // ---------------------------------------------------------------------

  Future<Result<List<HeldAmount>>> fetchHeldAmounts() {
    return guard(() async {
      final rows = await _db
          .from('held_amounts')
          .select()
          .eq('user_id', _userId)
          .order('held_on', ascending: false)
          .order('created_at', ascending: false)
          .order('id', ascending: false);
      return rows.map(HeldAmount.fromJson).toList();
    });
  }

  Future<Result<void>> createHeldAmount(HeldAmountDraft draft) {
    return guard(() async {
      await _db.rpc<String>('save_held_amount', params: _heldParams(draft));
    });
  }

  Future<Result<void>> updateHeldAmount(String id, HeldAmountDraft draft) {
    return guard(() async {
      await _db.rpc<String>(
        'save_held_amount',
        params: {..._heldParams(draft), 'p_held_id': id},
      );
    });
  }

  Map<String, dynamic> _heldParams(HeldAmountDraft draft) => {
    'p_direction': draft.direction.dbValue,
    'p_amount_minor': draft.amountMinor,
    'p_currency_code': draft.currencyCode,
    'p_counterparty': draft.counterparty,
    'p_held_on': draft.heldOn.toIso(),
    'p_title': draft.title,
    'p_notes': draft.notes,
    'p_account_id': draft.accountId,
    'p_transaction_id': draft.transactionId,
  };

  /// Marks a held amount settled on [settledOn], or active again when null.
  Future<Result<void>> setHeldAmountSettled(String id, PlainDate? settledOn) {
    return guard(() async {
      await _db.rpc<void>(
        'set_held_amount_settled',
        params: {'p_held_id': id, 'p_settled_on': settledOn?.toIso()},
      );
    });
  }

  Future<Result<void>> deleteHeldAmount(String id) {
    return guard(() async {
      await _db.rpc<void>('delete_held_amount', params: {'p_held_id': id});
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
