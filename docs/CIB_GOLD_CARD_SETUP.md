# CIB Gold Card — configuration recipe

Goal: configure the card in Finance Suit so it mirrors the real CIB Gold Card,
with the recurring fees **generated from the card's own rules** rather than
typed in as transactions. State reproduced: after the Jul-26 statement, as of
2026-08-07.

Companion document: `CIB_GOLD_CARD_GAP_ANALYSIS.md` (where each number below
comes from).

---

## 1. Card

Money → Accounts → add credit card.

| Field | Value | Why |
| --- | --- | --- |
| Name | CIB Gold | |
| Type | Credit card | |
| Currency | EGP | |
| Credit limit | **25,800.00** | statement |
| Statement closing day | **28** | see the warning below |
| Payment due day | **25** | statement |
| Last four digits | **6011** | |
| Minimum payment | **Percent · 5%** | matches the retail half of CIB's rule exactly |
| Foreign exchange markup | **3.00%** | matches all three FX lines on the statement exactly |
| Reminder lead days | 3 (or taste) | |
| Colour | your choice | display only |
| Status | Active | |

**Statement day.** The real cycle closes on the **last day of the month**; the
schema caps `statement_day` at 28, so 28 is the closest legal value. For this
card that happens to be harmless — nothing posted between 29 and 31 July except
`Month.Interest`, which the app does not model — so the July cycle still totals
2,610.76. It stops being harmless the first time you spend on the 29th–31st:
that charge lands in the following statement. This needs the one-line schema fix
to become correct rather than lucky.

**Minimum payment.** 5% reproduces CIB's retail component to the piastre
(5% × 2,610.76 = 130.53, and the app truncates the same way CIB does). It cannot
include the installments, which CIB always bills in full, so read the real
minimum as **the app's statement minimum + that month's installment dues**
(130.53 + 1,601.81 = 1,732.34 for 25-08).

---

## 2. Fee rules — the ones that generate themselves

Card detail → Fees → add rule. Pick any expense category you want the charge
filed under; the category drives reporting only, never the amount.

| Name | Fee type | Frequency | Calculation | Starts on | State |
| --- | --- | --- | --- | --- | --- |
| Annual fee | Annual membership | Annually | Fixed **300.00** | **2026-08-01** | Configured |
| Insurance fee — Solidarity | Insurance | Monthly | Fixed **25.00** | **2026-07-01** | Configured |
| Stamp duty | Stamp tax | Quarterly | Percent **0.05%** of *Highest balance in recent months*, look back **3** | **2026-07-01** | Configured |

That is the whole of what you asked for: from here the app posts 25.00 on the
1st of every month, 13.12 every 1 Jan/Apr/Jul/Oct, and 300.00 every 1 August,
each one landing in the right statement cycle, with no manual entry.

Two things to know about the generator:

- It advances **one period per refresh**. A rule back-dated to 2026-07-01 posts
  01-07 on the first facility refresh and 01-08 on the next, so pull-to-refresh
  the Money screen twice after creating the monthly rule. It is idempotent —
  refresh spam cannot double-charge.
- It is driven by `starts_on`, so back-dating is how you recover history. Do not
  back-date further than the day you want the first charge to exist.

**Stamp duty** uses CIB's published formula: 0.05% of the highest debit
balance in the last three months, charged quarterly. The *Highest balance in
recent months* basis computes exactly that peak from your ledger, so the app
reproduces 13.12 only once the transaction history covering the Apr–Jun peak
(26,240) exists in the app. For quarters the app didn't witness, reconcile
the generated charge against the statement figure.

### Rules to create as "unknown", not zero

These exist on the real card but you have never been charged them, so there is
no amount to enter. Creating them with state **Unknown** makes the card say "I
don't know this rate" instead of implying "no fee":

Late payment · Over limit · Cash advance (domestic) · Cash advance
(international) · Early settlement · Card replacement

An unknown rule never charges anything and never generates a transaction.

### The 3% foreign exchange markup

Your three FX fees (5.10, 29.99, 1.91) are exactly **3.00%** of the EGP-billed
amount, and only for foreign merchants billing in EGP — Google Play (billed
USD 25.00) got no fee because the markup rides inside the exchange rate.

This is the card's own **Foreign exchange markup** field from §1 (3.00%) —
not a Fee Rule. When entering a card purchase, flip **In foreign currency?**
and the app adds the markup as a second charge automatically:

- Netflix (170.00), OpenAI (999.99), Google Badoo (63.99), Cloudflare
  (536.75) — switch **on**: the 3% markup (5.10 / 29.99 / 1.91 / 16.10)
  posts alongside the purchase.
- Google Play (1,301.66, billed USD 25.00) — switch **off**: the bank's
  markup already rides inside the exchange rate, so a second charge here
  would double it.

The switch only appears on credit-card purchases and only does anything when
the card's markup field is set — leaving it on for a BNPL account, or for a
card with no rate configured, is always a no-op.

---

## 3. The two installment plans

Card detail → Installment purchase. **Pricing method matters** — it decides
whether your monthly figure matches the bank to the piastre.

### Plan A — ALTAREK AND ISLAM FOR (36 months, 2.5%/month)

| Field | Value |
| --- | --- |
| Title | ALTAREK AND ISLAM FOR |
| Purchase price | **13,000.00** |
| Purchased on | **2024-04-19** |
| Installments | **36** |
| First due on | **2024-05-25** |
| Pricing method | **Monthly amount** |
| Monthly payment | **551.87** |
| Already-paid installments | **27** |
| Down payment | 0 |

Use *Monthly amount*, **not** *Interest rate*. Both describe the same loan, but
the annuity path rounds to a total of 19,867.34 and bills 551.88 for the first
two months, while entering the monthly figure directly gives 36 dues of exactly
**551.87** — identical to the bank. The rate is still worth recording in the
plan's notes: *2.5% monthly, reducing balance*.

27 paid installments is correct as of today: the 28th is the one billed on
25-08, and it is still unpaid.

### Plan B — EL ARABY MAKRAM EBID (18 months, 0%)

| Field | Value |
| --- | --- |
| Title | EL ARABY MAKRAM EBID |
| Purchase price | **18,898.92** |
| Purchased on | **2026-03-17** |
| Installments | **18** |
| First due on | **2026-04-25** |
| Pricing method | **Manual fees**, fees **0** |
| Already-paid installments | **4** |
| Down payment | 0 |

The price is deliberately 18,898.92, not the 18,899.00 on the statement.
18 × 1,049.94 = 18,898.92, and CIB bills a flat 1,049.94 — so entering 18,899.00
makes the app spread the 0.08 residual across the first eight months (1,049.95),
which would mismatch every early statement. Taking the 0.08 off the price
instead gives 18 dues of exactly **1,049.94** and an outstanding of **14,699.16**
against the bank's 14,699.24. Expect CIB to collect that 0.08 in the final
installment (1,050.02 in Sep 2027); reconcile it then.

4 paid installments is correct: the 5th is billed on 25-08.

---

## 4. What still has to be entered as transactions

Config generates fees. It cannot invent purchases — those are yours to enter,
and they are what makes the balance match:

- **Jul cycle**: Netflix 170.00 (12-07), OpenAI 999.99 (13-07), Google Badoo
  63.99 (15-07) — each with **In foreign currency?** switched **on**, which
  generates the 5.10 / 29.99 / 1.91 FX markups automatically — and Google Play
  1,301.66 (16-07) with the switch **off**.
- **Aug cycle so far**: PAYMOB SigmaComputer 840.00 (02-08) and WE-Mobile
  783.87 (03-08) with the switch off; Cloudflare 536.75 (04-08) with it **on**
  — its 3% markup (16.10) will post with it and should appear on your next
  statement.
- **The 14-07 payment of 4,125.07**, as a facility payment against the June
  statement, if you model the June cycle at all.

Do **not** enter `Month.Interest 109.96` — it is Plan A's interest for the
month, already inside the 551.87 due. Entering it would double-count.

Google Play needs no FX fee: it was billed **USD 25.00** and converted at
52.0664, with CIB's markup inside the rate. Same for Cloudflare on 04-08. Only
foreign merchants who bill you *in EGP* attract the 3% line.

---

## 5. What matches after this, and what does not

| Figure (as of 2026-08-07) | Finance Suit | Real card | |
| --- | --- | --- | --- |
| Credit limit | 25,800.00 | 25,800.00 | ✅ |
| Due date | 2026-08-25 | 2026-08-25 | ✅ |
| Total amount due 25-08 | 4,212.57 | 4,212.57 | ✅ |
| Jul statement charges | 2,610.76 | 2,610.76 | ✅ |
| Plan A monthly | 551.87 | 551.87 | ✅ |
| Plan B monthly | 1,049.94 | 1,049.94 | ✅ |
| Plan B outstanding | 14,699.16 | 14,699.24 | ≈ (0.08, §3) |
| Generated fees | 300 / 25 / 13.12 on the right dates | same | ✅ |
| Foreign exchange fee | 3% generated per EGP-billed foreign purchase | same | ✅ |
| **Minimum due 25-08** | **130.53** | **1,732.34** | ❌ installments excluded |
| **Plan A outstanding** | **4,966.83** | **4,398.69** | ❌ unearned interest |
| **Card outstanding** | **24,762.37** | **24,304.27** | ❌ +458.10 |
| **Available credit** | **1,037.63** | **1,495.73** | ❌ −458.10 |
| Monthly EPP interest line | absent | 109.96 posted to balance | ❌ not modelled |

The ❌ rows are not configuration mistakes — no combination of settings fixes
them. Each needs a contained code change:

1. `statement_day` / `default_due_day` range 1–28 → 1–31 with clamping (the
   clamp helper already exists). Makes the cycle correct instead of coincidental.
2. A minimum-payment shape *installments in full + X% of the rest*. Turns
   130.53 into 1,732.34 — the one wrong number that can actually cost you a
   late-payment penalty.
3. Real amortisation for reducing-balance plans (per-installment principal and
   interest, outstanding = present value of remaining dues, monthly interest
   posted as a balance line). Fixes Plan A's outstanding, the card balance,
   available credit, utilisation, and early settlement together.

Items 1–2 are small. Item 3 is the real engineering, and it is the only one
that makes *outstanding* and *available credit* agree with the bank.
