# perpul — project context for agents

Flutter Android app, offline personal budget tracker ("Cek mampu beli"). Indonesian UI,
Rupiah. Single user, no network, no backend, no auth. Works entirely from a local sqflite DB.

## Product model

- Saldo (`balance`) is the single source of truth. Reserved money (`bills` + `savings`) is never
  spendable. `spendable = balance - bills - savings`.
- `J = spendable / daysLeft`, `daysLeft = max(1, payday - today)`. J is fixed for the whole
  payday cycle; opening the app decays `balance` by `J × elapsed days` (clamped so
  `balance >= bills + savings`). Daily spending needs no logging.
- Purchases ("Cek") are for larger one-off buys: they show the impact on spendable/jatah and
  only reduce `balance` when confirmed ("Beli"). All checks are logged; only bought ones move
  money. Logging alone (Cek) changes nothing.
- Payday cycle: `payday` is the next cycle end date, `payday_day` remembers the intended day
  (29–31 clamp to short months without drift — use `nextMonthly`, never `DateTime(y, m+1, d)`).
- Fixed income (`fixed_income = 1`): every crossed payday adds `salary` to balance and moves
  `savings_auto` from balance into savings, then advances the cycle.
- Irregular income (`fixed_income = 0`): no automatic money events; cycle still advances on the
  1st of the month as the jatah horizon; income is added manually via "Uang masuk"
  (`Store.addIncome`, raises jatah without restarting it). Salary and auto-savings are zeroed.

## Screens (bottom tabs, in order)

1. **Cek** (`DompetScreen`) — the main premise. Amount + Perlu/Pengen tag + note, optional
   multi-item list. Cek → result card → Beli / Pikir-pikir / Batal.
2. **Dompet** (`DashboardScreen`) — Saldo card with "Uang masuk", Jatah harian, Gajian/Awal bulan
   countdown, Tabungan, 3 latest log entries, "Mau beli?" → Cek tab. AppBar pencil = Setup.
3. **Tabungan** (`BillsScreen`) — savings pot (Tambah/Tarik), its riwayat, and a standalone
   "Simulasi nabung" calculator (`SimulationScreen`: pay-yourself-first 10/20/30%, living cost
   derived from what's left, emergency fund 3/6/12× it, 1/2/3-year projections; irregular mode
   defaults to 12× and "awal bulan" copy; nothing saved). Moving savings must
   NOT reset `last_decay`; setup/balance edits must.
4. **Catatan** (`HistoryScreen`) — checks + savings moves, filters and per-kind totals.

Savings moves are logged with a title (blank falls back to "Tambah/Tarik tabungan") and a
timestamp; they show in the Tabungan riwayat and Catatan. Deleting a logged move reverses its
money (`undoSavings`) and leaves `last_decay` alone.

`bills` and `savings_auto` stay in the schema/calc but have no UI; they keep their stored value.

Setup ("Isi Dulu") is also the first-run gate: gaji tetap/tidak tetap, uang sekarang, salary +
date (fixed only) or explanation (irregular). It resets the projection (`resetDecay: true`).

## Files

- `lib/calc.dart` — pure math, no Flutter: `daysLeft`, `spendable`, `dailyBudget`,
  `decayedBalance`, `checkPurchase`, `simulateSaving`, `monthlyOn`, `nextMonthly`,
  `paydayOnOrAfter`, `paydaysDue`.
- `lib/store.dart` — `ChangeNotifier` + sqflite. DB **v7** (`perpul.db`). `sync(now)` on startup and
  resume credits paydays then decays. `addSavings`/`withdrawSavings` (with `title`, return the moved
  amount; the UI shows a cap snackbar)/`deleteSavings`/`addIncome`/`setBalance`/`saveSettings`;
  `savingsLog` feeds the riwayat and Catatan.
- `lib/app.dart` — everything UI: shell/tabs, screens, `_AmountDialog`, `_ResultCard`,
  `_HistoryTile`, formatters (`money`, `amountText`, `shortDateLabel`, `dateLabel`, `percent`,
  `parseAmount`, `RupiahInputFormatter`), hand-rolled Indonesian weekday/month names (locale `id`
  for Material widgets only, no intl init).
- `lib/main.dart` — opens DB, `sync`, runs app; lifecycle resume calls `sync`.
- `test/` — calc (pure), format, history filters. 32 tests, plain `flutter test`.
- `assets/branding/perpul-logo.png` — source mark for the launcher icon (not bundled).
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` — adaptive icon: black background +
  the mark fitted inside the 66% safe zone; legacy `ic_launcher.png` mipmaps alongside.

Schema `settings`: `balance, bills, savings, fixed_income, salary, savings_auto, payday_day,
payday, install_date, last_decay` (single row id=1). `checks` rows: kind (`perlu`/`pengen`),
amount, note, result (Aman/Nggak aman), before/after spendable, created_at, bought.
`savings_log` rows: time, signed amount, title.

## Commands (Windows, PowerShell)

```
flutter analyze && flutter test          # must stay clean
flutter build apk --release              # build\app\outputs\flutter-apk\app-release.apk
adb -s <serial> install -r build\app\outputs\flutter-apk\app-release.apk
adb -s <serial> shell am force-stop com.perpul.app
adb -s <serial> shell monkey -p com.perpul.app -c android.intent.category.LAUNCHER 1
```

`flutter build apk --debug` is the faster loop while iterating. Toolchain: Flutter 3.47+/Dart 3.13+,
Android SDK, Python 3.14 (for device DB/UI inspection). No hot reload (flutter run dies with the
shell) — rebuild/reinstall instead. `rg` is not installed. Release builds use the Flutter template's
debug signing key; configure a keystore before distributing.

## Device verification workflow

- Target: a 720x1612 Android device. Set `$SERIAL` to your device id.
- Dump UI: `adb -s $SERIAL shell uiautomator dump /sdcard/x.xml`, then pull text with
  `adb -s $SERIAL shell "cat /sdcard/x.xml | base64"` → decode in Python (`xml.etree`). Flutter
  exposes semantics as `content-desc`; nav items are `<Label>\nTab x dari 4` buttons at
  y≈1383–1533. Windows redirects corrupt the XML encoding — always go through base64.
- Find tappable bounds, `adb -s $SERIAL shell input tap X Y`; hide keyboard with `keyevent 4`;
  wake the device (`keyevent KEYCODE_WAKEUP`) before dumping or uiautomator returns a null root node.
- Inspect/seed the DB: `adb -s $SERIAL shell "run-as com.perpul.app cat databases/perpul.db | base64"`,
  decode with sqlite3. To replace it: force-stop, `push` to `/data/local/tmp/`, `run-as ... rm -f
  databases/perpul.db-wal databases/perpul.db-journal`, `run-as ... cp`, relaunch. sqflite uses WAL,
  so read the main file only after the app has been stopped or you will see stale values. Delete
  `/sdcard` dumps afterwards.
- Check `adb -s $SERIAL logcat -d` for `FATAL|Unhandled Exception` after UI work.

## Conventions and pitfalls

- Copy is casual Indonesian, short: Saldo, Jatah harian, Gajian, Tabungan, Catatan,
  Mau beli?, Cek, Beli, Pikir-pikir, Batal, Tambah, Tarik, Uang masuk, Ubah isian, Dibeli.
- Money: `Rp 1.500.000`, dot thousands, no decimals. Dates in user-facing copy:
  `shortDateLabel` ("Min, 1 Nov"); ISO `dateLabel` only for log timestamps/footers.
- Kept minimal on purpose (ponytail): no state-management package, no intl, no charts, no
  animations beyond Material defaults. Prefer extending `calc.dart` + these widgets.
- Never dispose a `TextEditingController` while its `TextField` is still mounted/animating
  (`_dependents.isEmpty` crash) — let the State own it and defer row disposal a frame.
- Tabs live in an `IndexedStack`; each screen keeps its scroll/form state. Tab order and labels:
  Cek(0) / Dompet(1) / Tabungan(2) / Catatan(3); dashboard "Mau beli?" targets 0, "Lihat semua" 3.
- `saveSettings` normalizes the cycle: `paydayOnOrAfter(paydayDay, today)`, then roll forward if
  the result is not after today. Irregular mode forces day 1 and zero salary/auto-savings.
- Add a plain `test/` for any new pure logic; UI is verified on device.
- Launcher icon: keep the mark inside the middle 66% (72 of 108dp) so launcher masks don't clip it.
- Public repo hygiene: no device serials, local paths, keystores, DB dumps, or real financial data.
- `docs/perpul-brief.md` is the original brief (then called Ciai) and is stale; this file wins.

## Ideas not built yet

- Log income ("Uang masuk") as a Catatan entry — currently it only bumps `balance`.
- Keep `docs/superpowers/plans/` updated when starting a multi-step change.
