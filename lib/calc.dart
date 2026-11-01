DateTime monthlyOn(int year, int month, int day) {
  final last = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > last ? last : day);
}

// Next month on the intended day; clamps 29-31 to the last day of short months.
DateTime nextMonthly(DateTime d, [int? day]) {
  final y = d.month == 12 ? d.year + 1 : d.year;
  final m = d.month == 12 ? 1 : d.month + 1;
  return monthlyOn(y, m, day ?? d.day);
}

DateTime paydayOnOrAfter(int day, DateTime from) {
  final t = DateTime(from.year, from.month, from.day);
  final p = monthlyOn(t.year, t.month, day);
  if (!p.isBefore(t)) return p;
  final y = t.month == 12 ? t.year + 1 : t.year;
  final m = t.month == 12 ? 1 : t.month + 1;
  return monthlyOn(y, m, day);
}

// A picked future date is honored as-is; otherwise fall back to the recurring
// day-of-month. Lets Perbarui set a payday beyond the next month boundary.
DateTime nextPayday(
  DateTime picked,
  DateTime today,
  int paydayDay, {
  bool honorPicked = true,
}) {
  final start = DateTime(picked.year, picked.month, picked.day);
  final t = DateTime(today.year, today.month, today.day);
  var next = honorPicked && start.isAfter(t)
      ? start
      : paydayOnOrAfter(paydayDay, t);
  if (!next.isAfter(t)) next = nextMonthly(next, paydayDay);
  return next;
}

List<DateTime> paydaysDue(DateTime payday, DateTime today, [int? day]) {
  var p = DateTime(payday.year, payday.month, payday.day);
  final t = DateTime(today.year, today.month, today.day);
  final out = <DateTime>[];
  while (!t.isBefore(p) && out.length < 240) {
    out.add(p);
    p = nextMonthly(p, day);
  }
  return out;
}

int daysLeft(DateTime payday, DateTime today) {
  final d = DateTime(
    payday.year,
    payday.month,
    payday.day,
  ).difference(DateTime(today.year, today.month, today.day)).inDays;
  return d < 1 ? 1 : d;
}

double spendable({
  required double balance,
  required double bills,
  required double savings,
}) => balance - bills - savings;

double dailyBudget({
  required double balance,
  required double bills,
  required double savings,
  required int days,
}) {
  final s = spendable(balance: balance, bills: bills, savings: savings);
  return s <= 0 || days < 1 ? 0 : s / days;
}

// Never lets the daily plan eat into reserved money.
double decayedBalance({
  required double balance,
  required double bills,
  required double savings,
  required double daily,
  required int elapsed,
}) {
  if (elapsed <= 0 || daily <= 0) return balance;
  final reserved = bills + savings;
  if (balance <= reserved) return balance;
  final next = balance - daily * elapsed;
  return next < reserved ? reserved : next;
}

class PaydayCredit {
  const PaydayCredit({required this.balance, required this.savings});

  final double balance;
  final double savings;
}

// Salary lands, then the auto-savings slice is taken from what is left over.
PaydayCredit creditPayday({
  required double balance,
  required double bills,
  required double savings,
  required double salary,
  required double savingsAuto,
}) {
  final nextBalance = balance + salary;
  final room = nextBalance - bills - savings;
  final auto = savingsAuto > room ? (room < 0 ? 0.0 : room) : savingsAuto;
  return PaydayCredit(balance: nextBalance, savings: savings + auto);
}

// Reverse a logged savings move: adds return to the pot, withdrawals also
// return their money to saldo.
({double balance, double savings}) undoSavings({
  required double balance,
  required double savings,
  required double amount,
}) {
  final nextSavings = savings - amount;
  return (
    balance: amount < 0 ? balance - amount : balance,
    savings: nextSavings < 0 ? 0.0 : nextSavings,
  );
}

class SavingPlan {
  const SavingPlan({
    required this.target,
    required this.perPayday,
    required this.livingCost,
    required this.daily,
    required this.monthsToTarget,
    required this.projections,
  });

  final double target;
  final double perPayday;
  final double livingCost;
  final double daily;
  final int? monthsToTarget;

  // Pot after 12, 24, 36 months of the same payday saving.
  final List<double> projections;
}

// Pay yourself first: set the rate aside on payday, live on the rest until an
// emergency fund of `targetMonths` x that monthly living budget exists.
SavingPlan simulateSaving({
  required double income,
  required int days,
  required double rate,
  required int targetMonths,
}) {
  final perPayday = income * rate;
  final livingCost = income - perPayday;
  final target = livingCost * targetMonths;
  return SavingPlan(
    target: target,
    perPayday: perPayday,
    livingCost: livingCost,
    daily: livingCost <= 0 || days < 1 ? 0.0 : livingCost / days,
    monthsToTarget: perPayday <= 0 ? null : (target / perPayday).ceil(),
    projections: [
      for (final months in [12, 24, 36]) perPayday * months,
    ],
  );
}

class CheckResult {
  const CheckResult({
    required this.cost,
    required this.beforeSpendable,
    required this.afterSpendable,
    required this.dailyBefore,
    required this.dailyAfter,
    required this.daysLasts,
  });

  final double cost;
  final double beforeSpendable;
  final double afterSpendable;
  final double dailyBefore;
  final double dailyAfter;
  final double daysLasts;

  bool get affordable => afterSpendable >= 0;

  double get percentChange {
    if (dailyBefore == 0) return 0;
    return (dailyAfter - dailyBefore) / dailyBefore * 100;
  }
}

CheckResult checkPurchase({
  required double cost,
  required double spendable,
  required int daysLeft,
}) {
  final after = spendable - cost;
  final dailyBefore = spendable / daysLeft;
  final dailyAfter = after / daysLeft;
  final daysLasts = dailyBefore <= 0
      ? (after >= 0 ? double.infinity : 0.0)
      : after / dailyBefore;
  return CheckResult(
    cost: cost,
    beforeSpendable: spendable,
    afterSpendable: after,
    dailyBefore: dailyBefore,
    dailyAfter: dailyAfter,
    daysLasts: daysLasts,
  );
}
