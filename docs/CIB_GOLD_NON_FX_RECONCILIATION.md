# CIB Gold Non-FX Reconciliation

## Scope

This change fixes general credit-card and installment accounting defects and
applies the evidence-backed CIB Gold production reconciliation dated
2026-08-07. FX calculation remains owned by the separate FX implementation.
The known EGP 37.00 historical FX charge was intentionally not created.

## Accounting Changes

- Reducing-balance plans now retain exact principal, interest, scheduled
  payment, and closing-principal components for every due.
- Plan summaries separate current principal from future scheduled payments and
  future unaccrued interest.
- Historical imports record paid-through, as-of, current-posted, future, and
  bank-reconciled principal semantics without fabricating old repayments.
- Statement close, payment due, and installment due days are independent.
- Statement summaries expose ordinary charges, bank fees, installment dues,
  revolving base, total due, minimum due, payments, and remaining obligation.
- Minimum payment can use a percentage of non-installment revolving charges,
  plus installment dues and optional fees or overdue amounts.
- Purchase interest is a first-class card rule and activity classification.
- Confirmed bank-posted charges use versioned rules and idempotent
  reconciliation keys.
- Historical card payments can be corrected to transfers while a matching
  historical obligation preserves the imported current liability.

## Production Repair

The repair resolves the target by profile email and active card identity. It
checks fixture cardinality and the known before/final balance, runs in one
transaction, and is safe to rerun.

| Component | Before | After |
| --- | ---: | ---: |
| Samsung current principal | EGP 4,966.83 scheduled | EGP 4,398.69 principal |
| El Araby current principal | EGP 13,649.25 | EGP 14,699.24 |
| Non-installment/card liability | - | EGP 5,169.34 |
| Total outstanding, excluding missing FX | EGP 23,662.34 | EGP 24,267.27 |
| Available credit, excluding missing FX | EGP 2,137.66 | EGP 1,532.73 |

The repair also:

- changed statement close from day 25 to end of month and retained payment and
  installment due day 25;
- configured the 5% non-installment minimum basis plus installment dues and
  bank fees;
- recorded confirmed stamp duty of EGP 13.12 on 2026-07-01;
- recorded confirmed purchase interest of EGP 109.96 on 2026-08-01;
- reclassified the EGP 4,125.07 payment on 2026-07-14 from expense to facility
  repayment without changing current liability;
- preserved the existing annual fee, insurance rules, and 3% FX markup setting.

## Verification

- Database migrations replay from zero.
- All 35 pgTAP files pass: 728 assertions.
- All Flutter tests pass: 368 tests.
- `flutter analyze` reports no issues.
- Production repair succeeds twice with unchanged totals on the second run.
- Production statement cycles are 2026-07-01 through 2026-07-31, due
  2026-08-25, and 2026-08-01 through 2026-08-31, due 2026-09-25.
- The EGP 37.00 FX charge remains absent.
