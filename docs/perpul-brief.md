# Ciai — "Can I Afford It"

> Historical: this is the original brief for the app, then called Ciai. The app is now
> **perpul**; see `AGENTS.md` and `README.md` for current behavior.

## One-liner
A fully offline personal budget planner. Enter your balance and next payday, then check
whether a big purchase is affordable by seeing what it does to your daily spending budget.

## Platform
- Flutter (Dart), Android-first.
- Fully offline and local. No accounts, no network, no bank APIs.

## Money model
Two layers of state:

1. Money state
   - `balance`      = current money
   - `payday`       = next payday date
   - `daysLeft`     = max(1, payday - today)   # today counts as a day
   - `dailyBefore`  = spendable / daysLeft

2. Reserved money (separate panel: bills + savings)
   - `spendable`    = balance - reservedBills - reservedSavings

## Purchase check
Input: `cost`.

```
afterBalance = spendable - cost
dailyAfter   = afterBalance / daysLeft
daysLasts    = afterBalance / dailyBefore   # at current pace
verdict      = afterBalance >= 0
```

`daysLasts` = how long the money lasts if you keep spending at your CURRENT daily pace.

## Result screen
Show a before/after comparison plus a verdict line:
- spendable: before vs after
- daily budget: before vs after (with % change)
- days lasts: daysLeft vs daysLasts
- verdict: "Affordable" / "Not affordable"

Example: balance $1000, bills+savings $200, payday in 10 days, buy $300
- spendable: $800 -> $500
- daily: $80/day -> $50/day (-37.5%)
- lasts: 10 days -> 6.2 days
- verdict: Affordable

## Purchases mode
- Toggle: single item OR stacked list of planned purchases (combined impact).

## History / tracker
- Every check is saved locally with a timestamp.
- Record install date on first launch; history shows all checks since install.
- Uses a local DB (sqflite or drift).
- Note: only tracks purchases logged in-app, not real bank transactions.
- Data is lost on uninstall/clear-data unless export is added.

## Screens
1. Setup        — balance + payday (required).
2. Dashboard    — current daily state, days left.
3. Check        — enter purchase, see before/after result.
4. Bills & Savings — reserved amounts feeding `spendable`.
5. History      — saved checks since install.

## Defaults for open decisions (confirm before coding)
- Bills/savings: DEDUCT from spendable (reserved money).
- "Days lasts": at CURRENT pace (before purchase).
- Day counting: daysBetween(today, payday), minimum 1.
- Storage: sqflite (chosen now because history needs a DB).

## Environment (already installed and verified)
- Flutter 3.47.8 + Dart 3.13.7
- Android SDK + Android Studio
- `flutter doctor` = no issues

## Non-goals (v1)
- No bank integration, no cloud sync, no multi-user, no iOS build.
