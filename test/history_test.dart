import 'package:perpul/app.dart';
import 'package:perpul/calc.dart';
import 'package:perpul/store.dart';
import 'package:flutter_test/flutter_test.dart';

CheckRecord _rec(double cost, String? kind) => CheckRecord(
  time: DateTime(2026, 10, 29),
  cost: cost,
  items: null,
  kind: kind,
  result: const CheckResult(
    cost: 0,
    beforeSpendable: 1000,
    afterSpendable: 900,
    dailyBefore: 100,
    dailyAfter: 90,
    daysLasts: 10,
  ),
);

void main() {
  final all = [
    _rec(10, 'perlu'),
    _rec(20, 'pengen'),
    _rec(30, 'perlu'),
    _rec(40, null),
  ];

  test('filterChecks narrows by kind', () {
    expect(filterChecks(all, null).length, 4);
    expect(filterChecks(all, 'perlu').map((c) => c.cost), [10, 30]);
    expect(filterChecks(all, 'pengen').map((c) => c.cost), [20]);
  });

  test('kindTotals sums per tag and ignores untagged', () {
    expect(kindTotals(all), {'perlu': 40.0, 'pengen': 20.0});
  });

  final savings = [
    SavingsEntry(time: DateTime(2026, 10, 30, 8), amount: 50, title: 'Motor'),
    SavingsEntry(time: DateTime(2026, 10, 28, 9), amount: -20, title: 'Servis'),
  ];

  test('historyEntries merges checks and savings newest first', () {
    final rows = historyEntries(all, savings, null);
    expect(rows.length, 6);
    expect((rows.first as SavingsEntry).title, 'Motor');
    expect(rows[1], isA<CheckRecord>());
    expect((rows.last as SavingsEntry).title, 'Servis');
  });

  test('historyEntries filters kinds and savings', () {
    final tabungan = historyEntries(all, savings, 'tabungan');
    expect(tabungan.length, 2);
    expect(tabungan.every((r) => r is SavingsEntry), isTrue);
    final perlu = historyEntries(all, savings, 'perlu');
    expect(perlu.length, 2);
    expect(perlu.every((r) => r is CheckRecord), isTrue);
  });
}
