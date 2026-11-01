# Home polish + monthly salary + savings pot

> Historical plan (2026-10-29); some details have since changed. See `AGENTS.md` for current behavior.

## Goal
- Home shows: **Saldo** card, **Jatah harian** card, **Gajian** stat (countdown),
  **Sisihan** stat, 3 latest history entries, and "Mau beli?".
- Monthly salary auto-credits saldo on payday and starts a new cycle (no more
  "Gajian sudah lewat" banner).
- "Sisihan" tab becomes a savings pot: total, auto top-up per payday, manual
  Tambah/Tarik, plus tagihan.

## Approved decisions
- Salary auto-added to saldo on payday; cycle advances by one month.
- "Sampai gajian" becomes a **countdown**: "4 hari lagi" (caption shows payday
  weekday + date).
- Savings = pot with `otomatis nabung` amount per payday + manual add/withdraw.
- Home history = 3 latest entries (Cek and Dibeli), tap opens Catatan tab.
- Remove Home banner, remove "Uang sekarang" stat (replaced by Saldo card).

## Architecture / money model
- `balance` = all money (includes reserved). `bills` = reserved for bills.
  `savings` = reserved pot. `bisa dipakai = balance - bills - savings`.
- `jatah = bisa dipakai / days` (unchanged).
- On app open/resume (`Store.sync`):
  1. For every payday `p` where `today >= p`: decay the closing cycle up to `p`
     (daily jatah constant across a cycle), then `balance += salary`,
     `savings += min(savingsAuto, max(0, balance - bills - savings))`,
     `lastDecay = p`, `payday = nextMonthly(p)`.
  2. Decay from `lastDecay` to today with the new cycle's jatah.
- Decay reuses the invariant `jatah = spendable/days` by evaluating the daily
  budget at the cycle start (`lastDecay`), not at the target date.
- `nextMonthly` clamps day 29–31 to the last day of short months.

## Tech stack
- Flutter 3.47.8 / Dart 3.13.7, sqflite, no new dependencies.
- DB version 4: `settings.salary REAL`, `settings.savings_auto REAL`.

## Global constraints
- Indonesian UI copy, Rupiah formatting via existing `money`/`parseAmount`.
- Keep `Cek` → `Beli`/`Pikir-pikir`/`Batal` flow untouched.
- Ponytail: smallest diff, no new packages, one runnable check for new logic.
- Deploy loop: `flutter build apk --debug` → `adb install -r` → monkey launch.

## Known simplifications
- Payday day is stored separately (`settings.payday_day`, DB v5) so 29–31
  paydays survive short months (`31 Jan → 28 Feb → 31 Mar`).
- Catch-up assumes daily jatah was spent for missed days (same premise as the
  existing decay). `Perbarui` remains the escape hatch for real saldo.

---

## Task 1 — calc: monthly advance + due paydays (tested)
File: `lib/calc.dart`

```dart
DateTime nextMonthly(DateTime d) {
  final y = d.month == 12 ? d.year + 1 : d.year;
  final m = d.month == 12 ? 1 : d.month + 1;
  final last = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, d.day > last ? last : d.day);
}

List<DateTime> paydaysDue(DateTime payday, DateTime today) {
  var p = DateTime(payday.year, payday.month, payday.day);
  final t = DateTime(today.year, today.month, today.day);
  final out = <DateTime>[];
  while (!t.isBefore(p) && out.length < 240) {
    out.add(p);
    p = nextMonthly(p);
  }
  return out;
}
```

Tests in `test/calc_test.dart`:
- `nextMonthly(DateTime(2026, 1, 31))` → `2026-02-28` (2026 not leap).
- `nextMonthly(DateTime(2026, 12, 15))` → `2027-01-15`.
- `paydaysDue(2026-11-25, 2026-10-29)` → empty.
- `paydaysDue(2026-10-29, 2026-10-29)` → `[2026-10-29]`.
- `paydaysDue(2026-01-31, 2026-03-01)` → `[2026-01-31, 2026-02-28]`.

## Task 2 — DB v4 + salary/savings fields
File: `lib/store.dart`

1. Fields: `double salary = 0; double savingsAuto = 0;`
2. `version: 4`; `onCreate` adds `salary REAL NOT NULL DEFAULT 0`,
   `savings_auto REAL NOT NULL DEFAULT 0` to `settings`.
3. `onUpgrade`:
```dart
if (oldVersion < 4) {
  await db.execute(
    'ALTER TABLE settings ADD COLUMN salary REAL NOT NULL DEFAULT 0',
  );
  await db.execute(
    'ALTER TABLE settings ADD COLUMN savings_auto REAL NOT NULL DEFAULT 0',
  );
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
```
4. `_load`: read `salary`, `savings_auto`.
5. `saveSettings`: add `double? salary`, `double? savingsAuto` (null = keep),
   normalize payday to the next occurrence when it is today or past:
```dart
if (salary != null) this.salary = salary;
if (savingsAuto != null) this.savingsAuto = savingsAuto;
var next = dateOnly(payday);
final today = dateOnly(DateTime.now());
if (!next.isAfter(today)) next = nextMonthly(next);
```
   Persist both new columns.
6. `setBalance` unchanged.

## Task 3 — Store.sync: credit salary, decay per cycle, savings ops
File: `lib/store.dart`

Replace `applyDailyDecay` with:

```dart
Future<void> sync(DateTime now) async {
  if (payday == null) return;
  final today = dateOnly(now);
  for (final p in paydaysDue(payday!, now)) {
    await _decayTo(p);
    balance += salary;
    final room = balance - bills - savings;
    savings += savingsAuto > room ? (room < 0 ? 0 : room) : savingsAuto;
    lastDecay = p;
    payday = nextMonthly(p);
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
```

- `addCheck` calls `await sync(record.time)`.
- `main.dart` and `_CiaiAppState.didChangeAppLifecycleState` call `sync`.
- Savings ops:
```dart
Future<void> addSavings(double amount) async {
  final room = spendableNow < 0 ? 0.0 : spendableNow;
  savings += amount > room ? room : amount;
  await _db.update('settings', {'savings': savings}, where: 'id = 1');
  notifyListeners();
}

Future<void> withdrawSavings(double amount) async {
  final used = amount > savings ? savings : amount;
  savings -= used;
  final floor = bills + savings;
  balance = balance - used < floor ? floor : balance - used;
  lastDecay = dateOnly(DateTime.now());
  await _db.update('settings', {
    'balance': balance,
    'savings': savings,
    'last_decay': lastDecay!.toIso8601String(),
  }, where: 'id = 1');
  notifyListeners();
}
```

## Task 4 — Setup: salary field
File: `lib/app.dart`, `_SetupScreenState`
- Add `_salary` controller prefilled `amountText(store.salary)`.
- TextField "Gaji per bulan" (`RupiahInputFormatter`).
- `_save` passes `salary: parseAmount(_salary.text)`.

## Task 5 — Home redesign
File: `lib/app.dart`

- New label helper (below `dateLabel`):
```dart
const _weekdays = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu',
  'Sep', 'Okt', 'Nov', 'Des'];
String shortDateLabel(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
```
- `HomeShell`: pass `onHistory: () => setState(() => _index = 3)`.
- `DashboardScreen`: add `final VoidCallback onHistory;`
- Remove the payday-passed banner block and the `reserved` local.
- Card 1: label **Saldo**, `money(store.balance)` (`displaySmall`), caption
  `bisa dipakai ${money(store.spendableNow)}`.
- Card 2 (own card): label **Jatah harian**, `money(store.jatahNow)`,
  caption "Saldonya turun otomatis sesuai jatah."
- Stats row: `_Stat(label: 'Gajian', value: '${store.days} hari lagi', caption: 'gajian ${shortDateLabel(store.payday!)}')` and
  `_Stat(label: 'Sisihan', value: money(store.savings), caption: store.savingsAuto > 0 ? 'otomatis ${money(store.savingsAuto)} tiap gajian' : 'belum diatur')`.
- History block:
```dart
Row(children: [
  Expanded(child: Text('Catatan terakhir', style: theme.textTheme.titleMedium)),
  TextButton(onPressed: onHistory, child: const Text('Lihat semua')),
]),
if (store.history.isEmpty)
  const Text('Belum ada catatan.')
else
  for (final c in store.history.take(3))
    Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _HistoryTile(check: c, onTap: onHistory),
    ),
```
- `_HistoryTile` gains optional `VoidCallback? onTap` → `ListTile(onTap: onTap)`.
- Keep "Mau beli?" button last.

## Task 6 — Sisihan tab: savings pot
File: `lib/app.dart`, `_BillsScreenState`

- Rename state fields: keep `_bills`, add `_savingsAuto`; show pot from store.
- Layout:
  1. Card: "Tabungan" + `money(store.savings)` + caption
     'Otomatis ${money(store.savingsAuto)} tiap gajian. Tinggal dihitung dari saldo.'
  2. Row: `FilledButton('Tambah')` → `_AmountDialog` → `store.addSavings`,
     `OutlinedButton('Tarik')` → `_AmountDialog` → `store.withdrawSavings`.
  3. TextField "Buat tagihan" (`_bills`).
  4. TextField "Otomatis nabung tiap gajian" (`_savingsAuto`).
  5. `FilledButton('Simpan')` → `saveSettings(balance: store.balance, bills: ..., savings: store.savings, savingsAuto: ..., payday: store.payday!)`; snackbar 'Sisihan disimpan.'
- Generalize `_BalanceDialog` → `_AmountDialog({required title, required label, required initial})`;
  Dompet's Perbarui uses `_AmountDialog(title: 'Perbarui saldo', label: 'Uang asli sekarang', ...)`.

## Task 7 — Verify
1. `dart format lib test`; `flutter analyze` → no issues.
2. `flutter test` → all pass (15 existing + 5 new `nextMonthly`/`paydaysDue`).
3. `flutter build apk --debug`; `adb install -r`; force-stop; monkey launch.
4. On device:
   - Home: Saldo, Jatah harian (own card), Gajian "X hari lagi", Sisihan,
     3 history entries, no "Uang sekarang"/banner.
   - Tap history entry → Catatan tab; back to Home.
   - Sisihan: Tambah 50k (bisa dipakai drops, saldo same), Tarik 50k
     (saldo drops and pot drops), Simpan tagihan/auto-nabung persists.
   - Setup: salary persists; Dompet Cek/Beli/Pikir-pikir/Batal still fine.
   - `adb logcat -d -s flutter` → no exceptions.
5. Clean `/sdcard` dump files.

## Out of scope
- Background scheduling (sync only on open/resume, as before).
- Editing/deleting history entries.
- Multi-device sync, currency other than IDR.
