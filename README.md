# perpul

**Cek mampu beli sebelum jajan.** An offline, single-user budget tracker for Android with an
Indonesian UI and Rupiah formatting.

## What it does

- **Jatah harian** — enter your saldo and next payday; the app derives a fixed daily budget and
  decays the saldo as days pass.
- **Cek** — check a larger purchase against your spendable money and daily budget, then log it as
  Beli / Pikir-pikir / Batal.
- **Tabungan** — a savings pot with manual Tambah/Tarik, undo, and a pay-yourself-first simulator
  (10/20/30% plus an emergency fund).
- **Catatan** — checks and savings moves with filters and per-kind totals.
- **Fixed or irregular income** — salary auto-credits on payday, or add income manually.

No accounts, no network, no bank integrations, no analytics. Everything stays in a local sqflite
database.

## Build

```sh
flutter pub get
flutter test
flutter build apk --release
```

APK: `build/app/outputs/flutter-apk/app-release.apk`. Requires Flutter 3.47+ / Dart 3.13+.

## Notes

- Package id: `com.perpul.app`; database: `perpul.db` (Android Auto Backup enabled).
- Release builds currently use the Flutter template's debug signing key. Configure your own
  keystore before distributing.
- This is a personal project; no license is specified yet.
