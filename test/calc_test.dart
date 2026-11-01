import 'package:perpul/calc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('spec example', () {
    final r = checkPurchase(cost: 300, spendable: 800, daysLeft: 10);
    expect(r.afterSpendable, 500);
    expect(r.dailyBefore, 80);
    expect(r.dailyAfter, 50);
    expect(r.daysLasts, closeTo(6.25, 1e-9));
    expect(r.percentChange, closeTo(-37.5, 1e-9));
    expect(r.affordable, isTrue);
  });

  test('unaffordable purchase', () {
    final r = checkPurchase(cost: 900, spendable: 800, daysLeft: 10);
    expect(r.affordable, isFalse);
    expect(r.afterSpendable, -100);
    expect(r.daysLasts, lessThan(0));
  });

  test('daysLeft counts today and never drops below one', () {
    final today = DateTime(2026, 10, 29);
    expect(daysLeft(DateTime(2026, 10, 29), today), 1);
    expect(daysLeft(DateTime(2026, 10, 30), today), 1);
    expect(daysLeft(DateTime(2026, 11, 8), today), 10);
  });

  test('spendable subtracts reserved money', () {
    expect(spendable(balance: 1000, bills: 120, savings: 80), 800);
  });

  test('daily budget stays constant as days are consumed', () {
    final daily = dailyBudget(
      balance: 1000,
      bills: 100,
      savings: 100,
      days: 10,
    );
    expect(daily, 80);
    final after3 = decayedBalance(
      balance: 1000,
      bills: 100,
      savings: 100,
      daily: daily,
      elapsed: 3,
    );
    expect(after3, 760);
    expect(dailyBudget(balance: after3, bills: 100, savings: 100, days: 7), 80);
  });

  test('decay never eats reserved money', () {
    expect(
      decayedBalance(
        balance: 300,
        bills: 100,
        savings: 100,
        daily: 80,
        elapsed: 10,
      ),
      200,
    );
  });

  test('zero daily budget does not divide by zero', () {
    final r = checkPurchase(cost: 0, spendable: 0, daysLeft: 10);
    expect(r.daysLasts, double.infinity);
    expect(r.percentChange, 0);
  });

  test('nextMonthly clamps to short months and rolls the year', () {
    expect(nextMonthly(DateTime(2026, 1, 31)), DateTime(2026, 2, 28));
    expect(nextMonthly(DateTime(2026, 2, 28)), DateTime(2026, 3, 28));
    expect(nextMonthly(DateTime(2026, 12, 15)), DateTime(2027, 1, 15));
  });

  test('nextMonthly remembers the intended day after a short month', () {
    expect(nextMonthly(DateTime(2026, 2, 28), 31), DateTime(2026, 3, 31));
    expect(nextMonthly(DateTime(2026, 4, 30), 31), DateTime(2026, 5, 31));
    expect(nextMonthly(DateTime(2026, 2, 28), 30), DateTime(2026, 3, 30));
  });

  test('paydayOnOrAfter stays in this month when the day has not passed', () {
    expect(paydayOnOrAfter(31, DateTime(2026, 1, 10)), DateTime(2026, 1, 31));
    expect(paydayOnOrAfter(31, DateTime(2026, 2, 10)), DateTime(2026, 2, 28));
    expect(paydayOnOrAfter(1, DateTime(2026, 10, 29)), DateTime(2026, 11, 1));
    expect(paydayOnOrAfter(29, DateTime(2026, 10, 29)), DateTime(2026, 10, 29));
  });

  test('picked payday keeps its month while still ahead', () {
    expect(
      nextPayday(DateTime(2026, 12, 1), DateTime(2026, 10, 31), 1),
      DateTime(2026, 12, 1),
    );
    expect(
      nextPayday(DateTime(2026, 11, 15), DateTime(2026, 10, 31), 15),
      DateTime(2026, 11, 15),
    );
  });

  test('picked payday today rolls to the recurring day', () {
    expect(
      nextPayday(DateTime(2026, 10, 31), DateTime(2026, 10, 31), 31),
      DateTime(2026, 11, 30),
    );
    expect(
      nextPayday(DateTime(2026, 11, 1), DateTime(2026, 11, 1), 1),
      DateTime(2026, 12, 1),
    );
  });

  test('irregular mode ignores a picked month', () {
    expect(
      nextPayday(
        DateTime(2026, 12, 1),
        DateTime(2026, 10, 31),
        1,
        honorPicked: false,
      ),
      DateTime(2026, 11, 1),
    );
  });

  test('paydaysDue lists crossed paydays only', () {
    expect(paydaysDue(DateTime(2026, 11, 25), DateTime(2026, 10, 29)), isEmpty);
    expect(paydaysDue(DateTime(2026, 10, 29), DateTime(2026, 10, 29)), [
      DateTime(2026, 10, 29),
    ]);
    expect(paydaysDue(DateTime(2026, 1, 31), DateTime(2026, 3, 1)), [
      DateTime(2026, 1, 31),
      DateTime(2026, 2, 28),
    ]);
  });

  test('paydaysDue keeps a day-31 payday on the 31st', () {
    expect(paydaysDue(DateTime(2026, 1, 31), DateTime(2026, 4, 1), 31), [
      DateTime(2026, 1, 31),
      DateTime(2026, 2, 28),
      DateTime(2026, 3, 31),
    ]);
  });

  test('payday credits salary then caps auto-savings', () {
    final c = creditPayday(
      balance: 100,
      bills: 20,
      savings: 10,
      salary: 50,
      savingsAuto: 30,
    );
    expect(c.balance, 150);
    expect(c.savings, 40);
  });

  test('auto-savings never eats bills or goes negative', () {
    final c = creditPayday(
      balance: 0,
      bills: 20,
      savings: 0,
      salary: 10,
      savingsAuto: 50,
    );
    expect(c.balance, 10);
    expect(c.savings, 0);
  });

  test('zero auto-savings leaves the pot alone', () {
    final c = creditPayday(
      balance: 5,
      bills: 0,
      savings: 7,
      salary: 0,
      savingsAuto: 0,
    );
    expect(c.balance, 5);
    expect(c.savings, 7);
  });

  test('undoing a savings add returns it to spendable', () {
    final r = undoSavings(balance: 100, savings: 50, amount: 20);
    expect(r.balance, 100);
    expect(r.savings, 30);
  });

  test('undoing a withdrawal returns both saldo and pot', () {
    final r = undoSavings(balance: 80, savings: 30, amount: -20);
    expect(r.balance, 100);
    expect(r.savings, 50);
  });

  test('undo never drives the pot negative', () {
    final r = undoSavings(balance: 10, savings: 5, amount: 20);
    expect(r.savings, 0);
  });

  test('simulateSaving pays 20% first and projects 3 years', () {
    final p = simulateSaving(
      income: 1000,
      days: 30,
      rate: 0.2,
      targetMonths: 6,
    );
    expect(p.perPayday, 200);
    expect(p.livingCost, 800);
    expect(p.target, 4800);
    expect(p.daily, closeTo(800 / 30, 1e-9));
    expect(p.monthsToTarget, 24);
    expect(p.projections, [2400, 4800, 7200]);
  });

  test('simulateSaving handles no income', () {
    final p = simulateSaving(income: 0, days: 30, rate: 0.2, targetMonths: 6);
    expect(p.perPayday, 0);
    expect(p.livingCost, 0);
    expect(p.daily, 0);
    expect(p.monthsToTarget, isNull);
  });
}
