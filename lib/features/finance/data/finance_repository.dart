import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/card_fee_rule.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/facility_activity.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';
import 'package:work_tracker/features/finance/domain/held_amount.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/domain/recurring_rule.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/domain/transaction_macro.dart';
import 'package:work_tracker/features/finance/domain/transaction_query.dart';

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
    bool hideFromHome = false,
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
        'hide_from_home': hideFromHome,
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
    bool hideFromHome = false,
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
            'hide_from_home': hideFromHome,
            'notes': notes,
          })
          .eq('id', id)
          .eq('user_id', _userId);
    });
  }

  /// Home-tab visibility for accounts saved through the facility RPC,
  /// which owns every other facility field.
  Future<Result<void>> setHideFromHome(
    String accountId, {
    required bool hidden,
  }) {
    return guard(() async {
      await _db
          .from('accounts')
          .update({'hide_from_home': hidden})
          .eq('id', accountId)
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
          .or(
            'snoozed_until.is.null,snoozed_until.lte.${DateTime.now().toUtc().toIso8601String()}',
          )
          .order('scheduled_on', ascending: true);
      final actionable = occurrenceRows
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
      return collapsePendingIncome(actionable, today);
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
    bool includeExtraWorkInPercentage = true,
    String? extraWorkDestinationAccountId,
    bool rolloverBalanceEnabled = false,
    String? rolloverDestinationAccountId,
    String? categoryId,
    String? notes,
    String? sourceId,
    bool isActive = true,
  }) {
    return guard(() async {
      return _db.rpc<String>(
        'save_income_source_v4',
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
          'p_include_extra_work_in_percentage': includeExtraWorkInPercentage,
          'p_extra_work_destination_account_id': extraWorkDestinationAccountId,
          'p_rollover_balance_enabled': rolloverBalanceEnabled,
          'p_rollover_destination_account_id': rolloverDestinationAccountId,
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

  /// Accepts the part of an expected income that actually arrived and
  /// spawns a linked pending remainder for the shortfall, so the missing
  /// money stays visible until it is received or written off.
  Future<Result<String>> acceptIncomeOccurrencePartial({
    required String occurrenceId,
    required int receivedAmountMinor,
    required int expectedTotalMinor,
    required PlainDate receivedOn,
    String? notes,
    String? salaryPeriodId,
  }) {
    return guard(() async {
      return _db.rpc<String>(
        'accept_income_occurrence_partial',
        params: {
          'p_occurrence_id': occurrenceId,
          'p_received_amount_minor': receivedAmountMinor,
          'p_expected_total_minor': expectedTotalMinor,
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

  Future<Result<void>> snoozeIncomeOccurrence({
    required String occurrenceId,
    required DateTime snoozedUntil,
  }) {
    return guard(() async {
      await _db.rpc<void>(
        'snooze_income_occurrence',
        params: {
          'p_occurrence_id': occurrenceId,
          'p_snoozed_until': snoozedUntil.toUtc().toIso8601String(),
        },
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

  /// One filtered page of transactions, newest first.
  ///
  /// Paging is keyset, not offset: the cursor is the (business date,
  /// sort_at, id) triple the list is ordered by and the index covers, so
  /// scrolling never skips or repeats a row when transactions are added or
  /// removed mid-scroll.
  Future<Result<TransactionPage>> fetchTransactions(TransactionQuery input) {
    return guard(() async {
      final limit = input.limit.clamp(10, 100);
      var request = _db
          .from('financial_transactions')
          .select()
          .eq('user_id', _userId);

      final range = input.range;
      if (range != null) {
        request = request
            .gte('occurred_on', range.start.toIso())
            .lte('occurred_on', range.end.toIso());
      }
      final kinds = input.kind.kinds;
      if (kinds.isNotEmpty) {
        request = request.inFilter(
          'transaction_kind',
          kinds.map((kind) => kind.dbValue).toList(),
        );
      }
      final accountId = input.accountId;
      if (accountId != null) {
        request = request.or(
          'source_account_id.eq.$accountId,'
          'destination_account_id.eq.$accountId',
        );
      }
      final categoryId = input.categoryId;
      if (categoryId != null) {
        request = request.eq('category_id', categoryId);
      }
      final minAmountMinor = input.minAmountMinor;
      if (minAmountMinor != null) {
        request = request.gte('amount_minor', minAmountMinor);
      }
      final maxAmountMinor = input.maxAmountMinor;
      if (maxAmountMinor != null) {
        request = request.lte('amount_minor', maxAmountMinor);
      }
      final keyword = input.keyword?.trim();
      if (keyword != null && keyword.isNotEmpty) {
        final term = '%${_filterText(keyword)}%';
        request = request.or(
          'title.ilike.$term,notes.ilike.$term,counterparty.ilike.$term',
        );
      }
      final cursor = input.cursor;
      if (cursor != null) {
        final date = cursor.occurredOn.toIso();
        final sortAt = cursor.sortAt.toUtc().toIso8601String();
        request = request.or(
          'occurred_on.lt.$date,'
          'and(occurred_on.eq.$date,sort_at.lt.$sortAt),'
          'and(occurred_on.eq.$date,sort_at.eq.$sortAt,id.lt.${cursor.id})',
        );
      }

      // One row beyond the page tells the caller whether more exist without
      // a second count query.
      final rows = await request
          .order('occurred_on', ascending: false)
          .order('sort_at', ascending: false)
          .order('id', ascending: false)
          .limit(limit + 1);
      final items = rows
          .take(limit)
          .map(FinancialTransaction.fromJson)
          .toList();
      return TransactionPage(items: items, hasMore: rows.length > limit);
    });
  }

  /// PostgREST reads `or=(...)` as a comma-separated list and `ilike` treats
  /// `%`/`_` as wildcards, so user text is neutralized before it is spliced
  /// into a filter expression.
  String _filterText(String value) =>
      value.replaceAll('%', r'\%').replaceAll('_', r'\_').replaceAll(',', ' ');

  Future<Result<void>> createTransaction(TransactionDraft draft) {
    return guard(() async {
      await _db.from('financial_transactions').insert({
        'user_id': _userId,
        ...draft.toJson(),
      });
    });
  }

  /// Edits one ordinary transaction through the canonical role-aware RPC.
  ///
  /// The server owns the whole move: it locks the row and both accounts,
  /// validates eligibility, currency, and credit limits, applies the change
  /// once, and rebuilds the statement linkage. Writing the table directly
  /// would be rejected by the facility guard rails as soon as either side is
  /// a credit card or BNPL account.
  Future<Result<void>> updateTransaction(String id, TransactionDraft draft) {
    return guard(() async {
      await _db.rpc<String>(
        'update_expense_transaction',
        params: {
          'p_transaction_id': id,
          'p_account_id': draft.sourceAccountId ?? draft.destinationAccountId,
          'p_occurred_on': draft.occurredOn.toIso(),
          'p_amount_minor': draft.amountMinor,
          'p_category_id': draft.categoryId,
          'p_counterparty': draft.counterparty,
          'p_title': draft.title,
          'p_notes': draft.notes,
        },
      );
    });
  }

  /// Deletes one ordinary transaction on an asset or liability account. The
  /// RPC refuses installment, fee, repayment, and settled-statement rows so
  /// specialized history can never be dropped by the generic editor.
  Future<Result<void>> deleteTransaction(String id) {
    return guard(() async {
      await _db.rpc<void>(
        'delete_ledger_transaction',
        params: {'p_transaction_id': id},
      );
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
    'p_transaction_kind': draft.transactionKind.dbValue,
    'p_amount_minor': draft.amountMinor,
    'p_currency_code': draft.currencyCode,
    'p_counterparty': draft.counterparty,
    'p_held_on': draft.heldOn.toIso(),
    'p_title': draft.title,
    'p_notes': draft.notes,
    'p_account_id': draft.accountId,
    'p_category_id': draft.categoryId,
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

  // ---------------------------------------------------------------------
  // Credit facilities and installments
  // ---------------------------------------------------------------------

  Future<Result<List<CreditFacilitySummary>>> fetchCreditFacilities({
    bool includeArchived = false,
  }) {
    return guard(() async {
      var query = _db
          .from('credit_facility_summaries')
          .select()
          .eq('user_id', _userId);
      if (!includeArchived) {
        query = query.eq('is_archived', false);
      }
      final rows = await query.order('name', ascending: true);
      return rows.map(CreditFacilitySummary.fromJson).toList();
    });
  }

  /// Atomically creates or updates the liability account together with its
  /// facility settings through `save_credit_facility`.
  Future<Result<String>> saveCreditFacility(CreditFacilityDraft draft) {
    return guard(() async {
      final id = await _db.rpc<String>(
        'save_credit_facility',
        params: draft.toJson(),
      );
      return id;
    });
  }

  /// One plan by id, for the edit form.
  Future<Result<InstallmentPlan>> fetchInstallmentPlan(String planId) {
    return guard(() async {
      final row = await _db
          .from('installment_plan_summaries')
          .select()
          .eq('user_id', _userId)
          .eq('id', planId)
          .maybeSingle();
      if (row == null) {
        throw const NotFoundFailure(debugDetails: 'installment plan');
      }
      return InstallmentPlan.fromJson(row);
    });
  }

  Future<Result<List<InstallmentPlan>>> fetchInstallmentPlans({
    String? accountId,
  }) {
    return guard(() async {
      var query = _db
          .from('installment_plan_summaries')
          .select()
          .eq('user_id', _userId);
      if (accountId != null) {
        query = query.eq('account_id', accountId);
      }
      final rows = await query.order('created_at', ascending: false);
      return rows.map(InstallmentPlan.fromJson).toList();
    });
  }

  Future<Result<List<InstallmentDue>>> fetchInstallmentDues({
    String? accountId,
    String? planId,
  }) {
    return guard(() async {
      var query = _db
          .from('installment_due_statuses')
          .select()
          .eq('user_id', _userId);
      if (accountId != null) {
        query = query.eq('account_id', accountId);
      }
      if (planId != null) {
        query = query.eq('plan_id', planId);
      }
      final rows = await query
          .order('due_on', ascending: true)
          .order('sequence_number', ascending: true);
      return rows.map(InstallmentDue.fromJson).toList();
    });
  }

  /// Atomic installment purchase: books the financed expense (and optional
  /// down payment) once and generates the complete due schedule.
  Future<Result<String>> createInstallmentPlan(InstallmentPlanDraft draft) {
    return guard(() async {
      final id = await _db.rpc<String>(
        'create_installment_plan',
        params: draft.toJson(),
      );
      return id;
    });
  }

  /// Atomic facility repayment: one transfer from the asset account plus
  /// due allocations, oldest due first unless explicit allocations are sent.
  Future<Result<String>> payCreditFacility(FacilityPaymentDraft draft) {
    return guard(() async {
      final id = await _db.rpc<String>(
        'pay_credit_facility',
        params: draft.toJson(),
      );
      return id;
    });
  }

  Future<Result<void>> reverseFacilityPayment(String transactionId) {
    return guard(() async {
      await _db.rpc<String>(
        'reverse_facility_payment',
        params: {'p_transaction_id': transactionId},
      );
    });
  }

  Future<Result<void>> cancelInstallmentPlan(String planId) {
    return guard(() async {
      await _db.rpc<void>(
        'cancel_installment_plan',
        params: {'p_plan_id': planId},
      );
    });
  }

  /// Hard-deletes a facility that never carried any history; the server
  /// rejects everything else with `facility_has_history`.
  Future<Result<void>> deleteCreditFacility(String accountId) {
    return guard(() async {
      await _db.rpc<void>(
        'delete_credit_facility',
        params: {'p_account_id': accountId},
      );
    });
  }

  /// Freezes, closes, or re-activates a facility without touching history.
  Future<Result<void>> setCreditFacilityStatus(
    String accountId,
    FacilityStatus status,
  ) {
    return guard(() async {
      await _db.rpc<void>(
        'set_credit_facility_status',
        params: {'p_account_id': accountId, 'p_status': status.dbValue},
      );
    });
  }

  /// One ordinary credit-card purchase: a single expense assigned to the
  /// statement cycle of its business date. Never touches cash accounts.
  Future<Result<String>> chargeCreditCard({
    required String accountId,
    required String title,
    required String categoryId,
    required PlainDate occurredOn,
    required int amountMinor,
    String? notes,
    String? chargeId,
  }) {
    return guard(() async {
      final id = await _db.rpc<String>(
        'charge_credit_card',
        params: {
          'p_account_id': accountId,
          'p_title': title,
          'p_category_id': categoryId,
          'p_occurred_on': occurredOn.toIso(),
          'p_amount_minor': amountMinor,
          'p_notes': notes,
          'p_charge_id': chargeId,
        },
      );
      return id;
    });
  }

  /// One ordinary expense charged to a credit card or a BNPL facility: a
  /// single liability-backed expense that raises outstanding once and, on a
  /// credit card, joins the statement cycle of its business date. BNPL never
  /// gains an installment plan this way.
  Future<Result<String>> chargeLiabilityAccount({
    required String accountId,
    required String title,
    required String categoryId,
    required PlainDate occurredOn,
    required int amountMinor,
    String? notes,
    String? chargeId,
  }) {
    return guard(() async {
      final id = await _db.rpc<String>(
        'charge_liability_account',
        params: {
          'p_account_id': accountId,
          'p_title': title,
          'p_category_id': categoryId,
          'p_occurred_on': occurredOn.toIso(),
          'p_amount_minor': amountMinor,
          'p_notes': notes,
          'p_charge_id': chargeId,
        },
      );
      return id;
    });
  }

  /// Classified ledger activity of one facility, newest first. The server
  /// decides what each row is, so the client can route it to the correct
  /// editor without guessing.
  Future<Result<List<FacilityActivityItem>>> fetchFacilityActivity(
    String accountId, {
    int limit = 30,
  }) {
    return guard(() async {
      final rows = await _db
          .from('facility_activity_items')
          .select()
          .eq('user_id', _userId)
          .eq('account_id', accountId)
          .order('occurred_on', ascending: false)
          .order('sort_at', ascending: false)
          .order('transaction_id', ascending: false)
          .limit(limit);
      return rows.map(FacilityActivityItem.fromJson).toList();
    });
  }

  /// Statement cycles of one card, newest first.
  Future<Result<List<CardStatementSummary>>> fetchStatementSummaries(
    String accountId,
  ) {
    return guard(() async {
      final rows = await _db
          .from('credit_card_statement_summaries')
          .select()
          .eq('user_id', _userId)
          .eq('account_id', accountId)
          .order('cycle_close', ascending: false);
      return rows.map(CardStatementSummary.fromJson).toList();
    });
  }

  /// Rebuilds an unpaid plan in place from the edited draft.
  Future<Result<String>> updateInstallmentPlan(
    String planId,
    InstallmentPlanDraft draft,
  ) {
    return guard(() async {
      final id = await _db.rpc<String>(
        'update_installment_plan',
        params: draft.toUpdateJson(planId),
      );
      return id;
    });
  }

  /// Re-spreads the unpaid remainder of a partially paid plan.
  Future<Result<String>> restructureInstallmentPlan({
    required String planId,
    required int remainingTotalMinor,
    required int remainingCount,
    required PlainDate nextDueOn,
    String? changeNote,
  }) {
    return guard(() async {
      final id = await _db.rpc<String>(
        'restructure_installment_plan',
        params: {
          'p_plan_id': planId,
          'p_remaining_total_minor': remainingTotalMinor,
          'p_remaining_count': remainingCount,
          'p_next_due_on': nextDueOn.toIso(),
          'p_change_note': changeNote,
          'p_adjusted_on': PlainDate.today().toIso(),
        },
      );
      return id;
    });
  }

  /// Restructure history of one plan, oldest first.
  Future<Result<List<InstallmentPlanRevision>>> fetchPlanRevisions(
    String planId,
  ) {
    return guard(() async {
      final rows = await _db
          .from('installment_plan_revisions')
          .select()
          .eq('user_id', _userId)
          .eq('plan_id', planId)
          .order('revision', ascending: true);
      return rows.map(InstallmentPlanRevision.fromJson).toList();
    });
  }

  // ---------------------------------------------------------------------
  // Card fee rules
  // ---------------------------------------------------------------------

  /// Fee rules of one card, active first, then by name.
  Future<Result<List<CardFeeRule>>> fetchFeeRules(String accountId) {
    return guard(() async {
      final rows = await _db
          .from('credit_card_fee_rules')
          .select()
          .eq('user_id', _userId)
          .eq('account_id', accountId)
          .order('is_active', ascending: false)
          .order('name', ascending: true);
      return rows.map(CardFeeRule.fromJson).toList();
    });
  }

  /// Creates a fee rule, or replaces the editable fields of [ruleId].
  /// Rules are plain owner rows; only the generated charges are locked.
  Future<Result<void>> saveFeeRule(CardFeeRuleDraft draft, {String? ruleId}) {
    return guard(() async {
      if (ruleId == null) {
        await _db.from('credit_card_fee_rules').insert(draft.toJson(_userId));
      } else {
        // A schedule edit restarts the rule from its new start date.
        final patch = draft.toJson(_userId)
          ..remove('user_id')
          ..remove('account_id')
          ..['next_charge_on'] = null;
        await _db
            .from('credit_card_fee_rules')
            .update(patch)
            .eq('id', ruleId)
            .eq('user_id', _userId);
      }
    });
  }

  Future<Result<void>> setFeeRuleActive(String ruleId, {required bool active}) {
    return guard(() async {
      await _db
          .from('credit_card_fee_rules')
          .update({'is_active': active})
          .eq('id', ruleId)
          .eq('user_id', _userId);
    });
  }

  /// Deleting a rule stops future generation and drops its charge audit
  /// links; the already-booked fee expenses stay in the ledger.
  Future<Result<void>> deleteFeeRule(String ruleId) {
    return guard(() async {
      await _db
          .from('credit_card_fee_rules')
          .delete()
          .eq('id', ruleId)
          .eq('user_id', _userId);
    });
  }

  /// Generates every fee due through today, exactly once per rule and
  /// date; safe to call on every facility refresh.
  Future<Result<int>> applyCreditCardFees() {
    return guard(() async {
      final count = await _db.rpc<int>('apply_credit_card_fees');
      return count;
    });
  }

  // ---------------------------------------------------------------------
  // Recurring rules (expense / transfer automation)
  // ---------------------------------------------------------------------

  Future<Result<List<RecurringRule>>> fetchRecurringRules() {
    return guard(() async {
      final rows = await _db
          .from('recurring_rules')
          .select()
          .eq('user_id', _userId);
      final rules = rows.map(RecurringRule.fromJson).toList();
      rules.sort((left, right) {
        if (left.isActive != right.isActive) return left.isActive ? -1 : 1;
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });
      return rules;
    });
  }

  Future<Result<String>> saveRecurringRule({
    required String name,
    required RecurringRuleKind kind,
    required int amountMinor,
    required RecurringFrequency frequency,
    required int paymentDay,
    required PlainDate startDate,
    required int promptDaysBefore,
    required String sourceAccountId,
    String? destinationAccountId,
    String? categoryId,
    String? notes,
    String? ruleId,
    bool isActive = true,
  }) {
    return guard(() async {
      final id = await _db.rpc<String>(
        'save_recurring_rule',
        params: {
          'p_name': name,
          'p_rule_kind': kind.dbValue,
          'p_amount_minor': amountMinor,
          'p_frequency': frequency.dbValue,
          'p_payment_day': paymentDay,
          'p_start_date': startDate.toIso(),
          'p_prompt_days_before': promptDaysBefore,
          'p_source_account_id': sourceAccountId,
          'p_destination_account_id': destinationAccountId,
          'p_category_id': categoryId,
          'p_notes': notes,
          'p_rule_id': ruleId,
          'p_is_active': isActive,
        },
      );
      return id;
    });
  }

  Future<Result<void>> setRecurringRuleActive(
    String id, {
    required bool active,
  }) {
    return guard(() async {
      await _db
          .from('recurring_rules')
          .update({'is_active': active})
          .eq('id', id)
          .eq('user_id', _userId);
    });
  }

  /// Deleting a rule removes its pending schedule (cascade); accepted
  /// occurrences and their booked transactions stay in history.
  Future<Result<void>> deleteRecurringRule(String id) {
    return guard(() async {
      await _db
          .from('recurring_rules')
          .delete()
          .eq('id', id)
          .eq('user_id', _userId);
    });
  }

  /// Generate-on-read pending outflows: fills the schedule a month out,
  /// then returns the earliest actionable occurrence per rule inside its
  /// reminder window.
  Future<Result<List<PendingRecurring>>> fetchPendingRecurring(
    PlainDate today,
  ) {
    return guard(() async {
      await _db.rpc<int>(
        'materialize_recurring_occurrences',
        params: {'p_through_date': today.addDays(31).toIso()},
      );
      final ruleRows = await _db
          .from('recurring_rules')
          .select()
          .eq('user_id', _userId)
          .eq('is_active', true);
      final rules = ruleRows.map(RecurringRule.fromJson).toList();
      final byId = {for (final rule in rules) rule.id: rule};
      final occurrenceRows = await _db
          .from('recurring_occurrences')
          .select()
          .eq('user_id', _userId)
          .eq('status', IncomeOccurrenceStatus.pending.dbValue)
          .or(
            'snoozed_until.is.null,snoozed_until.lte.${DateTime.now().toUtc().toIso8601String()}',
          )
          .order('scheduled_on', ascending: true);
      final actionable = occurrenceRows
          .map(RecurringOccurrence.fromJson)
          .where((occurrence) {
            final rule = byId[occurrence.ruleId];
            return rule != null &&
                occurrence.scheduledOn <= today.addDays(rule.promptDaysBefore);
          })
          .map(
            (occurrence) => PendingRecurring(
              occurrence: occurrence,
              rule: byId[occurrence.ruleId]!,
            ),
          )
          .toList();
      final earliestByRule = <String, PendingRecurring>{};
      for (final item in actionable) {
        earliestByRule.putIfAbsent(item.rule.id, () => item);
      }
      final grouped = earliestByRule.values.toList();
      grouped.sort((left, right) {
        final leftDue = left.occurrence.scheduledOn <= today;
        final rightDue = right.occurrence.scheduledOn <= today;
        if (leftDue != rightDue) return leftDue ? -1 : 1;
        final date = left.occurrence.scheduledOn.compareTo(
          right.occurrence.scheduledOn,
        );
        if (date != 0) return date;
        final name = left.rule.name.toLowerCase().compareTo(
          right.rule.name.toLowerCase(),
        );
        if (name != 0) return name;
        return left.occurrence.id.compareTo(right.occurrence.id);
      });
      return grouped;
    });
  }

  Future<Result<String>> acceptRecurringOccurrence({
    required String occurrenceId,
    required int actualAmountMinor,
    required PlainDate paidOn,
    String? notes,
  }) {
    return guard(() async {
      final id = await _db.rpc<String>(
        'accept_recurring_occurrence',
        params: {
          'p_occurrence_id': occurrenceId,
          'p_actual_amount_minor': actualAmountMinor,
          'p_paid_on': paidOn.toIso(),
          'p_notes': notes,
        },
      );
      return id;
    });
  }

  Future<Result<void>> skipRecurringOccurrence(String occurrenceId) {
    return guard(() async {
      await _db.rpc<void>(
        'skip_recurring_occurrence',
        params: {'p_occurrence_id': occurrenceId},
      );
    });
  }

  Future<Result<void>> snoozeRecurringOccurrence({
    required String occurrenceId,
    required DateTime snoozedUntil,
  }) {
    return guard(() async {
      await _db.rpc<void>(
        'snooze_recurring_occurrence',
        params: {
          'p_occurrence_id': occurrenceId,
          'p_snoozed_until': snoozedUntil.toUtc().toIso8601String(),
        },
      );
    });
  }

  /// Hard-deletes a category; the server refuses with `category_in_use`
  /// while anything still references it.
  Future<Result<void>> deleteCategory(String id) {
    return guard(() async {
      await _db.rpc<void>(
        'delete_transaction_category',
        params: {'p_category_id': id},
      );
    });
  }
}

final financeRepositoryProvider = Provider<FinanceRepository>(
  (ref) => FinanceRepository(ref.watch(supabaseClientProvider)),
);
