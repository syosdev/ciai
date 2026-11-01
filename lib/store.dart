import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'calc.dart';

class CheckRecord {
  const CheckRecord({
    this.id,
    required this.time,
    required this.cost,
    required this.items,
    this.kind,
    this.actual = false,
    required this.result,
  });

  final int? id;
  final DateTime time;
  final double cost;
  final String? items;
  final String? kind;
  final bool actual;
  final CheckResult result;

  Map<String, Object?> toRow() => {
    'time': time.toIso8601String(),
    'cost': cost,
    'items': items,
    'kind': kind,
    'actual': actual ? 1 : 0,
    'before_spendable': result.beforeSpendable,
    'after_spendable': result.afterSpendable,
    'daily_before': result.dailyBefore,
    'daily_after': result.dailyAfter,
    'days_lasts': result.daysLasts,
    'affordable': result.affordable ? 1 : 0,
  };

  static CheckRecord fromRow(Map<String, Object?> r) => CheckRecord(
    id: r['id'] as int?,
    time: DateTime.parse(r['time']! as String),
    cost: (r['cost']! as num).toDouble(),
    items: r['items'] as String?,
    kind: r['kind'] as String?,
    actual: (r['actual'] as int? ?? 0) == 1,
    result: CheckResult(
      cost: (r['cost']! as num).toDouble(),
      beforeSpendable: (r['before_spendable']! as num).toDouble(),
      afterSpendable: (r['after_spendable']! as num).toDouble(),
      dailyBefore: (r['daily_before']! as num).toDouble(),
      dailyAfter: (r['daily_after']! as num).toDouble(),
      daysLasts: (r['days_lasts']! as num).toDouble(),
    ),
  );
}

class SavingsEntry {
  const SavingsEntry({
    this.id,
    required this.time,
    required this.amount,
    required this.title,
  });

  final int? id;
  final DateTime time;
  final double amount;
  final String title;

  static SavingsEntry fromRow(Map<String, Object?> r) => SavingsEntry(
    id: r['id'] as int?,
    time: DateTime.parse(r['time']! as String),
    amount: (r['amount']! as num).toDouble(),
    title: r['title']! as String,
  );
}

class Store extends ChangeNotifier {
  Store(this._db);

  final Database _db;

  double balance = 0;
  double bills = 0;
  double savings = 0;
  bool fixedIncome = true;
  double salary = 0;
  double savingsAuto = 0;
  int paydayDay = 1;
  DateTime? payday;
  DateTime? installDate;
  DateTime? lastDecay;
  List<CheckRecord> history = [];
  List<SavingsEntry> savingsLog = [];

  bool get isSetup => payday != null;

  int get days => payday == null ? 1 : daysLeft(payday!, DateTime.now());

  double get spendableNow =>
      spendable(balance: balance, bills: bills, savings: savings);

  double get jatahNow =>
      dailyBudget(balance: balance, bills: bills, savings: savings, days: days);

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static Future<Store> open() async {
    final db = await openDatabase(
      p.join(await getDatabasesPath(), 'perpul.db'),
      version: 7,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE settings (
            id INTEGER PRIMARY KEY,
            balance REAL NOT NULL,
            bills REAL NOT NULL,
            savings REAL NOT NULL,
            fixed_income INTEGER NOT NULL DEFAULT 1,
            salary REAL NOT NULL DEFAULT 0,
            savings_auto REAL NOT NULL DEFAULT 0,
            payday_day INTEGER NOT NULL DEFAULT 1,
            payday TEXT,
            install_date TEXT NOT NULL,
            last_decay TEXT
          )''');
        await db.execute('''
          CREATE TABLE checks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            time TEXT NOT NULL,
            cost REAL NOT NULL,
            items TEXT,
            kind TEXT,
            actual INTEGER NOT NULL DEFAULT 0,
            before_spendable REAL NOT NULL,
            after_spendable REAL NOT NULL,
            daily_before REAL NOT NULL,
            daily_after REAL NOT NULL,
            days_lasts REAL NOT NULL,
            affordable INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE savings_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            time TEXT NOT NULL,
            amount REAL NOT NULL,
            title TEXT NOT NULL
          )''');
        await db.insert('settings', {
          'id': 1,
          'balance': 0,
          'bills': 0,
          'savings': 0,
          'install_date': DateTime.now().toIso8601String(),
          'last_decay': DateTime.now().toIso8601String(),
        });
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE checks ADD COLUMN kind TEXT');
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE checks ADD COLUMN actual INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute('ALTER TABLE settings ADD COLUMN last_decay TEXT');
          // Start decay from today so upgrades don't retroactively spend.
          await db.update('settings', {
            'last_decay': DateTime.now().toIso8601String(),
          }, where: 'id = 1');
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE settings ADD COLUMN salary REAL NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE settings ADD COLUMN savings_auto REAL NOT NULL '
            'DEFAULT 0',
          );
          // Move the cycle forward without crediting a retroactive salary.
          final rows = await db.query('settings', where: 'id = 1');
          final raw = rows.isEmpty ? null : rows.first['payday'] as String?;
          if (raw != null) {
            final today = Store.dateOnly(DateTime.now());
            var next = Store.dateOnly(DateTime.parse(raw));
            while (!next.isAfter(today)) {
              next = nextMonthly(next);
            }
            await db.update('settings', {
              'payday': next.toIso8601String(),
              'last_decay': today.toIso8601String(),
            }, where: 'id = 1');
          }
        }
        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE settings ADD COLUMN payday_day INTEGER NOT NULL '
            'DEFAULT 1',
          );
          final rows = await db.query('settings', where: 'id = 1');
          final raw = rows.isEmpty ? null : rows.first['payday'] as String?;
          if (raw != null) {
            await db.update('settings', {
              'payday_day': DateTime.parse(raw).day,
            }, where: 'id = 1');
          }
        }
        if (oldVersion < 6) {
          await db.execute(
            'ALTER TABLE settings ADD COLUMN fixed_income INTEGER NOT NULL '
            'DEFAULT 1',
          );
        }
        if (oldVersion < 7) {
          await db.execute('''
            CREATE TABLE savings_log (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              time TEXT NOT NULL,
              amount REAL NOT NULL,
              title TEXT NOT NULL
            )''');
          final rows = await db.query('settings', where: 'id = 1');
          if (rows.isNotEmpty) {
            final saved = (rows.first['savings'] as num? ?? 0).toDouble();
            if (saved > 0) {
              await db.insert('savings_log', {
                'time':
                    (rows.first['install_date'] as String?) ??
                    DateTime.now().toIso8601String(),
                'amount': saved,
                'title': 'Saldo awal',
              });
            }
          }
        }
      },
    );
    final store = Store(db);
    await store._load();
    return store;
  }

  Future<void> _load() async {
    final rows = await _db.query('settings', where: 'id = 1');
    if (rows.isNotEmpty) {
      final r = rows.first;
      balance = (r['balance'] as num?)?.toDouble() ?? 0;
      bills = (r['bills'] as num?)?.toDouble() ?? 0;
      savings = (r['savings'] as num?)?.toDouble() ?? 0;
      fixedIncome = (r['fixed_income'] as int? ?? 1) == 1;
      salary = (r['salary'] as num?)?.toDouble() ?? 0;
      savingsAuto = (r['savings_auto'] as num?)?.toDouble() ?? 0;
      payday = r['payday'] == null
          ? null
          : DateTime.parse(r['payday']! as String);
      paydayDay = (r['payday_day'] as int?) ?? payday?.day ?? 1;
      installDate = DateTime.parse(r['install_date']! as String);
      lastDecay = r['last_decay'] == null
          ? null
          : DateTime.parse(r['last_decay']! as String);
    }
    final checks = await _db.query('checks', orderBy: 'time DESC');
    history = checks.map(CheckRecord.fromRow).toList();
    final savingsRows = await _db.query(
      'savings_log',
      orderBy: 'time DESC, id DESC',
    );
    savingsLog = savingsRows.map(SavingsEntry.fromRow).toList();
    notifyListeners();
  }

  Future<void> saveSettings({
    required double balance,
    required double bills,
    required double savings,
    required DateTime payday,
    bool? fixedIncome,
    double? salary,
    double? savingsAuto,
    bool resetDecay = false,
  }) async {
    this.balance = balance;
    this.bills = bills;
    this.savings = savings;
    if (fixedIncome != null) this.fixedIncome = fixedIncome;
    if (salary != null) this.salary = salary;
    if (savingsAuto != null) this.savingsAuto = savingsAuto;
    final today = dateOnly(DateTime.now());
    final picked = dateOnly(payday);
    if (this.fixedIncome) {
      paydayDay = picked.day;
    } else {
      paydayDay = 1;
      this.salary = 0;
      this.savingsAuto = 0;
    }
    final next = nextPayday(
      picked,
      today,
      paydayDay,
      honorPicked: this.fixedIncome,
    );
    this.payday = next;
    if (resetDecay || lastDecay == null) {
      lastDecay = today;
    }
    await _db.insert('settings', {
      'id': 1,
      'balance': balance,
      'bills': bills,
      'savings': savings,
      'fixed_income': this.fixedIncome ? 1 : 0,
      'salary': this.salary,
      'savings_auto': this.savingsAuto,
      'payday_day': paydayDay,
      'payday': next.toIso8601String(),
      'install_date': (installDate ?? DateTime.now()).toIso8601String(),
      'last_decay': lastDecay!.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  // Irregular income lands here; it raises the jatah, not restarts it.
  Future<void> addIncome(double amount) async {
    balance += amount;
    await _db.update('settings', {'balance': balance}, where: 'id = 1');
    notifyListeners();
  }

  // Sync the wallet with real money; restarts the projection from today.
  Future<void> setBalance(double value) async {
    balance = value;
    lastDecay = dateOnly(DateTime.now());
    await _db.update('settings', {
      'balance': balance,
      'last_decay': lastDecay!.toIso8601String(),
    }, where: 'id = 1');
    notifyListeners();
  }

  // Credits salary on every crossed payday, then spends the elapsed jatah.
  Future<void> sync(DateTime now) async {
    if (payday == null) return;
    final today = dateOnly(now);
    for (final p in paydaysDue(payday!, now, paydayDay)) {
      await _decayTo(p);
      final credit = creditPayday(
        balance: balance,
        bills: bills,
        savings: savings,
        salary: salary,
        savingsAuto: savingsAuto,
      );
      balance = credit.balance;
      savings = credit.savings;
      lastDecay = p;
      payday = nextMonthly(p, paydayDay);
    }
    await _decayTo(today);
    await _db.update('settings', {
      'balance': balance,
      'savings': savings,
      'payday': payday!.toIso8601String(),
      'last_decay': (lastDecay ?? today).toIso8601String(),
    }, where: 'id = 1');
    notifyListeners();
  }

  Future<void> _decayTo(DateTime target) async {
    final start = dateOnly(lastDecay ?? target);
    final elapsed = target.difference(start).inDays;
    if (elapsed <= 0) {
      lastDecay = start;
      return;
    }
    // The jatah stays constant inside a cycle, so read it at the cycle start.
    final daily = dailyBudget(
      balance: balance,
      bills: bills,
      savings: savings,
      days: daysLeft(payday!, start),
    );
    balance = decayedBalance(
      balance: balance,
      bills: bills,
      savings: savings,
      daily: daily,
      elapsed: elapsed,
    );
    lastDecay = target;
  }

  Future<double> addSavings(double amount, {String title = ''}) async {
    final room = spendableNow < 0 ? 0.0 : spendableNow;
    final moved = amount > room ? room : amount;
    if (moved <= 0) return 0;
    savings += moved;
    await _recordSavings(moved, title, 'Tambah tabungan', {'savings': savings});
    return moved;
  }

  Future<double> withdrawSavings(double amount, {String title = ''}) async {
    final moved = amount > savings ? savings : amount;
    if (moved <= 0) return 0;
    savings -= moved;
    final floor = bills + savings;
    balance = balance - moved < floor ? floor : balance - moved;
    lastDecay = dateOnly(DateTime.now());
    await _recordSavings(-moved, title, 'Tarik tabungan', {
      'balance': balance,
      'savings': savings,
      'last_decay': lastDecay!.toIso8601String(),
    });
    return moved;
  }

  Future<void> _recordSavings(
    double amount,
    String title,
    String fallback,
    Map<String, Object?> settings,
  ) async {
    final clean = title.trim();
    final entry = SavingsEntry(
      time: DateTime.now(),
      amount: amount,
      title: clean.isEmpty ? fallback : clean,
    );
    late int id;
    await _db.transaction((txn) async {
      id = await txn.insert('savings_log', {
        'time': entry.time.toIso8601String(),
        'amount': entry.amount,
        'title': entry.title,
      });
      await txn.update('settings', settings, where: 'id = 1');
    });
    savingsLog = [
      SavingsEntry(
        id: id,
        time: entry.time,
        amount: entry.amount,
        title: entry.title,
      ),
      ...savingsLog,
    ];
    notifyListeners();
  }

  // Undo a savings move: an add goes back to spendable, a Tarik is reversed.
  Future<void> deleteSavings(int id) async {
    final i = savingsLog.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final next = undoSavings(
      balance: balance,
      savings: savings,
      amount: savingsLog[i].amount,
    );
    balance = next.balance;
    savings = next.savings;
    await _db.transaction((txn) async {
      await txn.delete('savings_log', where: 'id = ?', whereArgs: [id]);
      await txn.update('settings', {
        'balance': balance,
        'savings': savings,
      }, where: 'id = 1');
    });
    savingsLog = List.of(savingsLog)..removeAt(i);
    notifyListeners();
  }

  Future<void> addCheck(CheckRecord record) async {
    await sync(record.time);
    late int id;
    await _db.transaction((txn) async {
      id = await txn.insert('checks', record.toRow());
      if (record.actual) {
        balance -= record.cost;
        await txn.update('settings', {
          'balance': balance,
          'last_decay': (lastDecay ?? dateOnly(record.time)).toIso8601String(),
        }, where: 'id = 1');
      }
    });
    history = [
      CheckRecord(
        id: id,
        time: record.time,
        cost: record.cost,
        items: record.items,
        kind: record.kind,
        actual: record.actual,
        result: record.result,
      ),
      ...history,
    ];
    notifyListeners();
  }

  // Undo a logged check; one that was bought puts its money back.
  Future<void> deleteCheck(int id) async {
    final i = history.indexWhere((c) => c.id == id);
    if (i < 0) return;
    final record = history[i];
    await _db.transaction((txn) async {
      await txn.delete('checks', where: 'id = ?', whereArgs: [id]);
      if (record.actual) {
        balance += record.cost;
        await txn.update('settings', {'balance': balance}, where: 'id = 1');
      }
    });
    history = List.of(history)..removeAt(i);
    notifyListeners();
  }
}
