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
import 'package:work_tracker/features/finance/domain/income_source.dart';
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
      final row = await _db
          .from('accounts')
          .select()
          .eq('id', id)
          .eq('user_id', _userId)
          .single();
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
          .eq('id', id)
          .eq('user_id', _userId);
    });
  }

  Future<Result<void>> setArchived(String id, {required bool archived}) {
    return guard(() async {
      // Archiving the default account would leave the user without one;
      // the archived account also loses its default flag.
      final patch = <String, dynamic>{'is_archived': archived};
      if (archived) patch['is_default'] = false;
      await _db
          .from('accounts')
          .update(patch)
          .eq('id', id)
          .eq('user_id', _userId);
    });
  }

  Future<Result<void>> setDefaultAccount(String id) {
    return guard(() async {
      final userId = _userId;
      final target = await _db
          .from('accounts')
          .select('id')
          .eq('id', id)
          .eq('user_id', userId)
          .eq('is_archived', false)
          .maybeSingle();
      if (target == null) {
        throw const NotFoundFailure(debugDetails: 'account not found');
      }

      // Partial unique index allows one default among active accounts.
      await _db
          .from('accounts')
          .update({'is_default': false})
          .eq('user_id', userId)
          .eq('is_default', true);
      await _db
          .from('accounts')
          .update({'is_default': true})
          .eq('id', id)
          .eq('user_id', userId);
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
    String? parentCategoryId,
  }) {
    return guard(() async {
      await _db.from('transaction_categories').insert({
        'user_id': _userId,
        'name': name,
        'category_kind': kind.dbValue,
        'icon': icon,
        'parent_category_id': parentCategoryId,
      });
    });
  }

  // ---------------------------------------------------------------------
  // Recurring income automation
  // ---------------------------------------------------------------------

  Future<Result<List<IncomeSource>>> fetchIncomeSources({
    bool includeInactive = true,
  }) {
    return guard(() async {
      var query = _db
          .from('income_sources')
          .select('*, income_source_allocations(*)')
          .eq('user_id', _userId);
      if (!includeInactive) query = query.eq('is_active', true);
      final rows = await query.order('name', ascending: true);
      final sources = rows.map(IncomeSource.fromJson).toList();
      sources.sort((left, right) {
        final active = (right.isActive ? 1 : 0) - (left.isActive ? 1 : 0);
        if (active != 0) return active;
        final salary =
            (left.kind == IncomeSourceKind.salary ? 0 : 1) -
            (right.kind == IncomeSourceKind.salary ? 0 : 1);
        if (salary != 0) return salary;
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });
      return sources;
    });
  }

  Future<Result<List<PendingIncome>>> fetchPendingIncome(PlainDate today) {
    return guard(() async {
      await _db.rpc<int>(
        'materialize_income_occurrences',
        params: {'p_through_date': today.addDays(31).toIso()},
      );
      final sourceRows = await _db
          .from('income_sources')
          .select('*, income_source_allocations(*)')
          .eq('user_id', _userId)
          .eq('is_active', true);
      final sources = sourceRows.map(IncomeSource.fromJson).toList();
      final byId = {for (final source in sources) source.id: source};
      final occurrenceRows = await _db
          .from('income_occurrences')
          .select()
          .eq('user_id', _userId)
          .eq('status', IncomeOccurrenceStatus.pending.dbValue)
          .order('scheduled_on', ascending: true);
      return occurrenceRows
          .map(IncomeOccurrence.fromJson)
          .where((occurrence) {
            final source = byId[occurrence.incomeSourceId];
            return source != null &&
                occurrence.scheduledOn <=
                    today.addDays(source.promptDaysBefore);
          })
          .map(
            (occurrence) => PendingIncome(
              occurrence: occurrence,
              source: byId[occurrence.incomeSourceId]!,
            ),
          )
          .toList();
    });
  }

  Future<Result<String>> saveIncomeSource({
    required String name,
    required IncomeSourceKind kind,
    required int expectedAmountMinor,
    required String currencyCode,
    required int paymentDay,
    required PlainDate startDate,
    required int promptDaysBefore,
    required String primaryAccountId,
    required List<IncomeAllocation> allocations,
    String? categoryId,
    String? notes,
    String? sourceId,
    bool isActive = true,
  }) {
    return guard(() async {
      return _db.rpc<String>(
        'save_income_source_v2',
        params: {
          'p_name': name,
          'p_source_kind': kind.dbValue,
          'p_expected_amount_minor': expectedAmountMinor,
          'p_currency_code': currencyCode,
          'p_payment_day': paymentDay,
          'p_start_date': startDate.toIso(),
          'p_prompt_days_before': promptDaysBefore,
          'p_primary_account_id': primaryAccountId,
          'p_category_id': categoryId,
          'p_allocations': [
            for (final allocation in allocations) allocation.toPayload(),
          ],
          'p_notes': notes,
          'p_source_id': sourceId,
          'p_is_active': isActive,
        },
      );
    });
  }

  Future<Result<void>> setIncomeSourceActive(
    String id, {
    required bool active,
  }) {
    return guard(() async {
      await _db
          .from('income_sources')
          .update({'is_active': active})
          .eq('id', id)
          .eq('user_id', _userId);
    });
  }

  Future<Result<String>> acceptIncomeOccurrence({
    required String occurrenceId,
    required int actualAmountMinor,
    required PlainDate receivedOn,
    String? notes,
    String? salaryPeriodId,
  }) {
    return guard(() async {
      return _db.rpc<String>(
        'accept_income_occurrence',
        params: {
          'p_occurrence_id': occurrenceId,
          'p_actual_amount_minor': actualAmountMinor,
          'p_received_on': receivedOn.toIso(),
          'p_notes': notes,
          'p_salary_period_id': salaryPeriodId,
        },
      );
    });
  }

  Future<Result<void>> skipIncomeOccurrence(String occurrenceId) {
    return guard(() async {
      await _db.rpc<void>(
        'skip_income_occurrence',
        params: {'p_occurrence_id': occurrenceId},
      );
    });
  }

  Future<Result<void>> renameCategory(String id, String name) {
    return guard(() async {
      await _db
          .from('transaction_categories')
          .update({'name': name})
          .eq('id', id)
          .eq('user_id', _userId);
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
          .eq('id', id)
          .eq('user_id', _userId);
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
          .eq('id', id)
          .eq('user_id', _userId);
    });
  }

  Future<Result<void>> deleteTransaction(String id) {
    return guard(() async {
      await _db
          .from('financial_transactions')
          .delete()
          .eq('id', id)
          .eq('user_id', _userId);
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
      await _db
          .from('transaction_macros')
          .delete()
          .eq('id', id)
          .eq('user_id', _userId);
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
