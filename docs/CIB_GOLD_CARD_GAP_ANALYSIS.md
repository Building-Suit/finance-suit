# CIB Gold Card — statement vs. Finance Suit gap analysis

Reference date: **2026-08-07**.

Sources analysed:

- `Statements_Jul26.xls` — CIB statement, cycle **Jul-26** (closing 2026-07-31,
  due 2026-08-25).
- `TRANSACTION_20260807160878.csv` — card transaction list 2026-07-01 → 2026-08-07.
- `TRANSACTION_20260807160802.csv` — card EPP (installment) list.
- Two CIB app screenshots, one per EPP plan.

Everything below is derived from those files only; no rate was assumed.

---

## 1. What the bank actually says

| Field | Value |
| --- | --- |
| Product | MASTER GOLD CHIP NEW |
| Card number | 5335 \*\*\*\* \*\*\*\* 6011 |
| Card limit | 25,800.00 EGP |
| Statement date | Jul-26 (cycle closes **31-07**) |
| Payment due date | **2026-08-25** |
| Opening balance | 23,223.00 |
| Closing balance | 21,818.65 |
| Total amount due | 4,212.57 |
| Minimum payment due | 1,732.34 |
| Available credit limit | 3,981.35 |

### 1.1 The cycle reconciles exactly

```
opening                                  23,223.00
+ purchases   170.00 + 999.99 + 63.99 + 1,301.66   = 2,535.64
+ fees        25.00 + 13.12 + 5.10 + 29.99 + 1.91  =    75.12
+ Month.Interest (EPP)                                 109.96
- payment received (14-07)                          -4,125.07
= closing                                          21,818.65   ✓ matches
```

### 1.2 Every headline figure is a derivable formula

| Bank figure | Derivation | Check |
| --- | --- | --- |
| Opening balance 23,223.00 | EPP principal outstanding 19,097.93 + previous cycle's unpaid dues 4,125.07 | exact |
| Total amount due 4,212.57 | retail + fees this cycle 2,610.76 + **both monthly EPP installments in full** 1,601.81 | exact |
| Minimum payment 1,732.34 | **100% of EPP installments** 1,601.81 + **5% of retail-and-fees** 130.538 → truncated | exact |
| Available credit 3,981.35 | 25,800.00 − closing balance 21,818.65 | exact |
| Month.Interest 109.96 | EPP principal outstanding 4,398.69 × **2.5% / month** = 109.967 → truncated | exact |
| FX fee | **3.00%** of the EGP-billed amount (5.10/170, 29.99/999.99, 1.91/63.99) | exact |

So the CIB model is: **minimum payment = installments in full + 5% of
everything else, and money amounts truncate at 2 decimals** (not round).

### 1.3 The two EPP plans

| | Plan A | Plan B |
| --- | --- | --- |
| Merchant (statement) | ALTAREK AND ISLAM FOR | EL ARABY MAKRAM EBID |
| Merchant (CSV) | `INSTALLMENT UNDER PROCESSING` (placeholder) | EL ARABY MAKRAM EBID |
| Enrolled | 2024-04-19 | 2026-03-17 |
| Original amount | 13,000.00 | 18,899.00 |
| Tenor | 36 | 18 |
| Monthly rate | **2.5% reducing balance** | 0% |
| Monthly payment | 551.87 | 1,049.94 |
| This cycle | #28 of 36 (441.91 principal + 109.96 interest) | #5 of 18 (1,049.94 principal) |
| Outstanding principal | 4,398.69 | 14,699.24 |
| Maturity | 2027-04-25 | 2027-09-25 |
| First due | 2024-05-25 | 2026-04-25 |

Plan A is a textbook **annuity**: `13,000 × 0.025 / (1 − 1.025⁻³⁶) = 551.87`
to the piastre, and `4,398.69` is exactly the present value of the 9
payments still to come (including the one billed on 25-08). Plan B is flat
0% with `18,899 / 18 = 1,049.94` and the 0.08 residual carried to the end,
not spread over the early installments.

Two things worth knowing about the source files:

- The EPP CSV's `Outstanding Amount` column is **not** outstanding — it is the
  monthly installment (551.87 / 1,049.94). Don't import it as a balance.
- The CIB app screenshots' "remaining installments" counter (8 of 36, 13 of 18)
  **excludes** the installment currently being billed, while the outstanding
  amount on the same screen **includes** it. Both are self-consistent only if
  you read the counter as "after 25-08".

### 1.4 Post-statement activity (Aug cycle so far, 2,485.62)

| Date | Description | Amount |
| --- | --- | --- |
| 01-08 | Annual fee | 300.00 |
| 01-08 | INSURANCE FEE - SOLIDARITY | 25.00 |
| 02-08 | PAYMOB - SigmaComputer GIZA | 840.00 |
| 03-08 | WE-Mobile-Post Giza | 783.87 |
| 04-08 | CLOUDFLARE SAN FRANCISCO | 536.75 |

No stamp duty on 01-08 (it is **quarterly** — it posted 01-07), and no FX fee
line against Cloudflare, which matters — see §4.2.

---

## 2. What Finance Suit already gets right

Credit for what is in place, because it is most of the hard part:

- `statement_bounds_for` handles day clamping and due-day rollover, so a
  "closes on the 31st, due on the 25th of next month" card is expressible in
  principle (see §4.1 for why it is not expressible in practice).
- Cycle membership, statement items, allocations, payment reversal, and the
  versioned fee-rule engine with tri-state `unknown` rules (a fee nobody has
  observed yet never silently charges zero) — exactly the right shape for this.
- `highest_statement_due_lookback` + `lookback_cycles` is precisely the basis
  Egyptian quarterly stamp duty needs.
- `apply_when` on foreign rules, cash-advance/wallet subtypes, penalties,
  reconciliation (expected vs. actual), tenor rate tiers, `p_paid_installments`
  for importing a plan mid-life.
- The `upcoming_due_minor` composition (statement remaining + installment dues
  within a month) reproduces **Total amount due 4,212.57** correctly.

---

## 3. What is calculated wrong

### 3.1 Reducing-balance plans front-load all interest into the balance

`resolve_plan_financing` computes the annuity payment, multiplies by the count,
and books **principal + all future interest as one card charge on day one**
(`create_installment_plan`). There is no amortisation schedule, so there is no
per-installment principal/interest split and no declining principal.

For Plan A, entered faithfully with 27 paid installments:

| | Finance Suit | Bank | Error |
| --- | --- | --- | --- |
| Total payable | 19,867.34 | (never a balance) | — |
| Remaining / outstanding | 4,966.83 | 4,398.69 | **+568.14** |
| Monthly due #1–2 | 551.88 | 551.87 | +0.01 |
| Principal paid to date (`principalPaidMinor`, pro rata) | 10,111.3 | 8,601.31 | −1,509.99 |

The pro-rata split documented in `InstallmentPlan.principalPaidMinor` is
correct for a **flat** plan and wrong for a **reducing** one: this month the
bank allocates 80.1% of the payment to principal (441.91/551.87), pro rata says
65.4%. So "how much of the item do I actually own" is understated by ~1,510 EGP
on this plan alone.

### 3.2 Outstanding, available credit and utilisation are therefore all off

| | Finance Suit | Bank | Error |
| --- | --- | --- | --- |
| Plan A component | 4,966.83 | 4,398.69 (+109.96 interest posted) | |
| Plan B component | 14,699.20 | 14,699.24 | −0.04 |
| Retail + fees | 2,610.76 | 2,610.76 | 0 |
| **Outstanding** | **22,276.79** | **21,818.65** | **+458.14** |
| **Available credit** | **3,523.21** | **3,981.35** | **−458.14** |
| Utilisation | 86.34% | 84.57% | +1.77 pp |

The app will tell you that you have 458 EGP less headroom than you do, and the
`insufficient_credit` guard in `charge_credit_card` will refuse purchases the
bank would approve.

### 3.3 Minimum payment cannot express CIB's rule

`credit_card_statement_summaries.minimum_due_minor` applies
`min_payment_basis_points` to the **statement charges only**. Installment dues
are not statement items, so with `percent` at 5% the app computes **130.53**
against the bank's **1,732.34** — a 1,601.81 understatement, i.e. it would tell
you a payment that misses the minimum and triggers a late-payment penalty.

`MinPaymentMethod` needs a fifth shape: *installments in full + X% of the rest*
(with the existing `greater_of` floor still applicable to the percentage part).

### 3.4 Rounding residual sits on the wrong installments

`create_installment_plan` gives the first `total mod count` dues one extra
minor unit; CIB keeps every installment equal and lets the residual fall at the
end. Plan B: the app schedules 1,049.95 for the first 8 months, the bank bills
1,049.94 for all 18. Small, but it makes every early reconciliation mismatch.

### 3.5 Early settlement over-charges by the unearned interest

`settle_installment_plan_early` pays `sum(remaining dues)` — the full remaining
total payable. For Plan A that is **4,966.83** where the bank would settle the
**4,398.69** principal (plus whatever early-settlement fee applies). It also
derives the fee basis `remaining_principal` from the same pro-rata split, so a
percentage early-settlement fee is computed on 2,888.7 instead of 4,398.69.

### 3.6 Rounding direction

CIB truncates (1,732.348 → 1,732.34; 109.967 → 109.96). The fee engine and
`resolve_plan_financing` use `round()`. Sub-piastre, but it is a guaranteed
one-piastre reconciliation diff on every percentage-derived figure.

---

## 4. What is missing

### 4.1 `statement_day` cannot be the end of the month — blocking

```sql
statement_day smallint check (statement_day between 1 and 28)
```

This card closes on **31-07**. The tightest configuration available today is
day 28, which puts the 29–31 July charges (including `Month.Interest` dated
31-07) into the August cycle and shifts every cycle boundary. `default_due_day`
has the same 1–28 cap; 25 is fine here, but cards due on the 30th exist.

Needed: allow 1–31 and clamp (`clamp_day_of_month` already does exactly this),
or add an explicit `statement_closes_on_month_end boolean`.

### 4.2 No way to express "foreign merchant, billed in home currency"

The three FX fees all pair with EGP-billed foreign merchants. Google Play was
billed **USD 25.00** (the statement carries the `USD25,00` line, converted at
1,301.66/25 = 52.0664) and attracted **no** FX fee — the markup is inside the
applied rate. Cloudflare on 04-08 likewise has no FX line yet.

`ForeignApplyWhen` offers `currency_differs`, `merchant_outside_home`, `either`,
`both`. All four mis-fire here: `merchant_outside_home` would charge Google Play
an extra 39.05, `currency_differs` would skip Netflix/OpenAI/Badoo. The needed
condition is **merchant outside home AND currency does not differ**.

Also: `p_original_amount_minor` / `p_original_currency_code` /
`p_exchange_rate` are accepted by `charge_credit_card` but only stored inside
the fee charge's `calculation_snapshot`, and only when a rule fires. They
belong on the charge itself so a USD-billed transaction keeps its original
amount and implied rate even when no fee line exists.

### 4.3 No purchase (revolving) interest at all

Nothing in the schema charges interest on a carried retail balance: no
`interest` fee type, no `statement_carry` trigger, no grace-period concept
("no interest if the statement was paid in full"). This cycle it did not bite
because the previous statement was paid in full on 14-07, and the only interest
line is EPP interest. The moment a statement is partly paid, the app silently
under-reports the balance.

The nearest available workaround — a monthly `percentage` rule on
`statement_balance` — reads the **latest** cycle by `cycle_close`, which is the
still-open one, and has no grace-period condition. Not a substitute.

### 4.4 EPP monthly interest is never posted as a balance line

The bank posts `Month.Interest 109.96` to the balance each cycle and bills
principal+interest as the installment. Finance Suit has no such posting because
all interest was capitalised at creation (§3.1). Consequence: the statement view
can never be reconciled line-by-line against the paper statement.

### 4.5 The statement view has no balances

`CardStatementSummary` carries charges / paid / remaining / minimum. It has no
**opening balance**, **closing balance**, or **available credit at close** — the
four numbers at the top of the bank statement, and the ones that make
reconciliation self-checking (§1.1 is exactly the check that cannot be run).

### 4.6 Backend features with no client reach

> **Update (2026-08-07):** the FX row of this table is closed, twice over.
> First pass: the fee editor learned to derive trigger kind from the fee
> type (with `apply_when`, including a *foreign merchant billed in home
> currency* condition, and the `transaction_amount` basis), and card charges
> carried a merchant & currency choice through `charge_credit_card`. Second
> pass, superseding it for the common case: a flat `fx_markup_basis_points`
> rate lives directly on `credit_facility_settings`, and card charges carry
> a plain "in foreign currency?" switch through `charge_liability_account` —
> no fee rule to create first. The two mechanisms are independent and can
> coexist; the rule-based one remains available for a card whose FX pricing
> needs a condition, clamp, or lookback the flat rate can't express. A
> `highest daily balance` basis was also added, so quarterly stamp duty
> computes CIB's real base. Tenor rates, early settlement, and
> cash-advance/wallet subtypes remain unwired below.

| Feature | Backend | Repository | UI |
| --- | --- | --- | --- |
| Foreign / cash-advance / wallet charges | ✅ `charge_credit_card` params | ❌ `chargeCreditCard` sends 7 of 13 params | ❌ |
| `trigger_kind` on a fee rule | ✅ | ✅ in draft | ❌ never set — every rule is `schedule` |
| `apply_when` | ✅ | ❌ | ❌ |
| `percent_basis = transaction_amount` | ✅ | ✅ | ❌ not in the picker list |
| Installment tenor rate tiers | ✅ table + `resolve_tenor_rate` | ❌ no RPC/CRUD | ❌ |
| `settle_installment_plan_early` | ✅ | ❌ | ❌ |

So today **the 3% FX fee, the cash-advance fee, the over-limit fee and the
early-settlement fee are all unreachable from the app**, and
`PlanPricingMethod.cardTenorDefault` can only fail with `no_tenor_rate`.

### 4.7 No statement import / reconciliation entry point

Both CIB exports are trivially machine-readable and the engine already has
`reconcile_fee_charge` and `ChargeReconciliationStatus`
(`expected/confirmed/adjusted/waived/reversed/missing`). What is missing is the
importer that walks a statement, matches items, and drives that lifecycle —
plus handling for `waived` / `missing`, which `reconcile_fee_charge` explicitly
leaves out.

### 4.8 Onboarding an existing card

`CreditFacilityDraft` deliberately has no opening-owed input ("new facilities
always start at zero debt"). To model this card you must reproduce 21,818.65 of
history. `p_paid_installments` covers the plans; there is no equivalent for the
**4,125.07 previous-cycle statement balance** or for a card imported mid-cycle.

---

## 5. Fees this card needs

Observed, with the evidence for each:

| Fee | Type | Frequency | Calculation | Trigger | Evidence |
| --- | --- | --- | --- | --- | --- |
| Annual fee | `annual_membership` | `annually` | fixed **300.00**, starts 2026-08-01 | `schedule` | 01-08 line |
| Solidarity insurance | `insurance` | `monthly` | fixed **25.00**, 1st of month | `schedule` | 01-07 and 01-08 lines |
| Stamp duty | `stamp_tax` | `quarterly` | ~**13.12**, 1st of Jan/Apr/Jul/Oct | `schedule` | 01-07 only; absent 01-08 |
| Foreign exchange fee | `foreign_transaction` | `per_transaction` | **3.00%** of `transaction_amount` | `foreign_transaction`, EGP-billed foreign merchant | 3/3 exact matches |
| EPP interest | *not a fee* | monthly | **2.5%/month reducing** on remaining principal | plan amortisation | 109.96 = 4,398.69 × 2.5% |
| Late payment | `late_payment` | — | **unknown** | `late_payment_missed_minimum` | never incurred |
| Over limit | `over_limit` | — | **unknown** | `over_limit_event` | never incurred |
| Cash advance (domestic / international) | `cash_advance` | — | **unknown** | `domestic_cash_advance` / `international_cash_advance` | never used |
| Early settlement | `early_settlement` | — | **unknown** | `early_settlement` | never used |
| Purchase/revolving interest | **no type exists** | monthly | unknown rate, grace if paid in full | **no trigger exists** | previous statement paid in full |

On stamp duty: one observation cannot pin a rate. 13.12 implies a basis of
26,240 at 0.05% per quarter, which is *above* the 25,800 limit, so the basis is
not simply the credit limit and probably tracks the highest balance in the
quarter. Configure it as `state = unknown` (or fixed 13.12) and let
`reconcile_fee_charge` confirm it against the Apr–Jun statements before trusting
a formula. This is precisely what the tri-state rule is for.

The four `unknown` rules matter as much as the configured ones: they make the
card honest about what it does not know instead of implying "no fee".

---

## 6. What to add to Credit Card creation

Existing inputs: name, type, currency, credit limit, colour, statement day,
due day, last 4 digits, reminder lead days, min-payment method (+fixed/percent),
facility status, notes.

**Blocking additions**

1. **Statement closing day 1–31 / month-end flag** — §4.1. Without this the CIB
   Gold card cannot be configured correctly at all.
2. **Minimum-payment shape "installments in full + X% of the rest"** — §3.3.
   Enter 5% and the card reproduces 1,732.34.
3. **Purchase interest block** — monthly (or annual) rate, `flat`/`reducing`,
   and "grace period: no interest when the previous statement was paid in
   full". Today an unpaid statement accrues nothing.

**Needed to reproduce this statement**

4. **Installment tenor table** on the card: rows like *36 months → 2.5%
   monthly, reducing* and *18 months → 0%*, so `cardTenorDefault` works and a
   new EPP purchase prices itself. Backend exists; expose it.
5. **Fee-rule editor: `trigger_kind` + `apply_when` + `transaction_amount`
   basis**, plus a `foreign_merchant_home_currency` option — §4.2, §4.6.
6. **Charge entry: subtype (purchase / cash advance / wallet) and foreign
   flags + original amount, currency, applied rate** — pass the params
   `charge_credit_card` already accepts, and persist them on the charge.
7. **Opening state for an imported card**: previous statement balance and its
   due date, so onboarding does not require replaying history — §4.8.

**Worth adding**

8. **Cash advance limit** (a sub-limit of the credit limit) — CIB Gold has one
   and nothing models it.
9. **Product/scheme name** ("MASTER GOLD CHIP NEW") — free text; drives nothing,
   but it is what the statement is titled and it disambiguates two Gold cards.
10. **Rounding policy** (truncate vs. round) per card — §3.6.

---

## 7. Setting this card up today (with the gaps as they are)

1. Card: name *CIB Gold*, EGP, limit **25,800.00**, due day **25**, statement
   day **28** *(wrong — the closest the schema allows; §4.1)*, last four
   **6011**, min payment `percent` **5%** *(will read 130.53, not 1,732.34)*.
2. Fee rules (all `schedule`, since the UI sets no other trigger): annual fee
   300 annually from 2026-08-01; insurance 25 monthly from 2026-07-01; stamp
   duty 13.12 quarterly from 2026-07-01 — mark it `unknown` if you would rather
   not assert the amount.
3. Plan A: purchase 13,000.00 on 2024-04-19, 36 installments, first due
   2024-05-25, pricing `interest_rate` **250 bp monthly, reducing**, paid
   installments **27**. The app will show 4,966.83 outstanding against the
   bank's 4,398.69 (§3.1).
4. Plan B: purchase 18,899.00 on 2026-03-17, 18 installments, first due
   2026-04-25, pricing `manual_fees` with 0 fees, paid installments **4**.
   Dues 1–8 will read 1,049.95 instead of 1,049.94 (§3.4).
5. Charges: enter the four purchases and the three FX fees **manually as
   ordinary charges** — the 3% rule cannot be created from the UI (§4.6).
6. Do not expect `Month.Interest` to appear; it does not exist in the model
   (§4.4).

Expected result after that setup: total amount due **4,212.57 ✓**, minimum due
**130.53 ✗** (should be 1,732.34), outstanding **22,276.79 ✗** (should be
21,818.65), available credit **3,523.21 ✗** (should be 3,981.35).

---

## 8. Fix order

1. `statement_day` / `default_due_day` range → 1–31 with clamping. *(Small
   migration, unblocks correct cycles.)*
2. Minimum-payment shape *installments in full + X%*. *(One view change; turns
   the most dangerous wrong number — the one that causes real penalties — into
   the right one.)*
3. Amortisation schedule for reducing plans: per-installment principal/interest,
   outstanding = PV of remaining dues, monthly interest posted as a balance
   line, early settlement at principal, equal installments with the residual
   last. *(The largest change; fixes §3.1, §3.2, §3.4, §3.5, §4.4 together.)*
4. Client reach for the existing engine: trigger kind, `apply_when` (plus the
   new home-currency-foreign-merchant option), `transaction_amount` basis,
   charge subtypes and FX metadata, tenor rates, early settlement.
5. Purchase interest with grace period.
6. Statement balances on the cycle view, then the statement importer driving
   the reconciliation lifecycle.
