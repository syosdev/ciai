import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'calc.dart';
import 'store.dart';

String _grouped(int v) {
  final digits = v.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return buf.toString();
}

String money(double v) {
  final rounded = v.round();
  return '${rounded < 0 ? '-' : ''}Rp ${_grouped(rounded)}';
}

String amountText(double v) => '${v < 0 ? '-' : ''}${_grouped(v.round())}';

const kindLabels = {'perlu': 'Perlu', 'pengen': 'Pengen'};

List<CheckRecord> filterChecks(List<CheckRecord> all, String? kind) =>
    kind == null ? all : all.where((c) => c.kind == kind).toList();

Map<String, double> kindTotals(List<CheckRecord> checks) {
  final totals = <String, double>{};
  for (final c in checks) {
    final kind = c.kind;
    if (kind == null) continue;
    totals[kind] = (totals[kind] ?? 0) + c.cost;
  }
  return totals;
}

List<Object> historyEntries(
  List<CheckRecord> checks,
  List<SavingsEntry> savings,
  String? filter,
) {
  final rows = <Object>[
    ...filterChecks(checks, filter),
    if (filter == null || filter == 'tabungan') ...savings,
  ];
  DateTime timeOf(Object row) =>
      row is CheckRecord ? row.time : (row as SavingsEntry).time;
  rows.sort((a, b) => timeOf(b).compareTo(timeOf(a)));
  return rows;
}

// ponytail: cursor always jumps to the end; add caret math only if mid-edit
// changes become a real need.
class RupiahInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return TextEditingValue.empty;
    final text = _grouped(int.parse(digits));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

String percent(double v) {
  final value = v.abs().toStringAsFixed(1).replaceAll('.', ',');
  if (v > 0) return 'naik $value%';
  if (v < 0) return 'turun $value%';
  return 'tetap';
}

const _weekdays = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

String shortDateLabel(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

String dateLabel(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String timeLabel(DateTime d) =>
    '${dateLabel(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

double parseAmount(String text) =>
    double.tryParse(text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;

Future<void> _deleteSavingsEntry(
  BuildContext context,
  Store store,
  SavingsEntry entry,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Hapus catatan tabungan?'),
      content: Text(entry.title),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Hapus'),
        ),
      ],
    ),
  );
  if (ok != true || entry.id == null) return;
  await store.deleteSavings(entry.id!);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Catatan tabungan dihapus.')));
}

class PerpulApp extends StatefulWidget {
  const PerpulApp({super.key, required this.store});

  final Store store;

  @override
  State<PerpulApp> createState() => _PerpulAppState();
}

class _PerpulAppState extends State<PerpulApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.store.sync(DateTime.now()).ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'perpul',
      debugShowCheckedModeBanner: false,
      locale: const Locale('id'),
      supportedLocales: const [Locale('id')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) => widget.store.isSetup
            ? HomeShell(store: widget.store)
            : SetupScreen(store: widget.store),
      ),
    );
  }
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.store, this.canCancel = false});

  final Store store;
  final bool canCancel;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final TextEditingController _balance;
  late final TextEditingController _salary;
  late bool _fixed;
  DateTime? _payday;
  String? _error;

  @override
  void initState() {
    super.initState();
    _balance = TextEditingController(
      text: widget.store.payday == null ? '' : amountText(widget.store.balance),
    );
    _salary = TextEditingController(text: amountText(widget.store.salary));
    _fixed = widget.store.fixedIncome;
    _payday = widget.store.payday;
  }

  @override
  void dispose() {
    _balance.dispose();
    _salary.dispose();
    super.dispose();
  }

  Future<void> _pickPayday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _payday ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _payday = picked);
  }

  Future<void> _save() async {
    if (_fixed && _payday == null) {
      setState(() => _error = 'Pilih tanggal gajian dulu ya.');
      return;
    }
    await widget.store.saveSettings(
      balance: parseAmount(_balance.text),
      bills: widget.store.bills,
      savings: widget.store.savings,
      fixedIncome: _fixed,
      salary: parseAmount(_salary.text),
      payday: _payday ?? paydayOnOrAfter(1, DateTime.now()),
      resetDecay: true,
    );
    if (mounted && widget.canCancel) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Isi Dulu'),
        automaticallyImplyLeading: widget.canCancel,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('Isi uang kamu sekarang dan cara kamu dapat uang.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Gaji tetap'),
                selected: _fixed,
                onSelected: (_) => setState(() => _fixed = true),
              ),
              ChoiceChip(
                label: const Text('Tidak tetap'),
                selected: !_fixed,
                onSelected: (_) => setState(() => _fixed = false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _balance,
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Uang kamu sekarang',
              prefixText: 'Rp ',
              border: OutlineInputBorder(),
            ),
          ),
          if (_fixed) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _salary,
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Gaji per bulan',
                prefixText: 'Rp ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickPayday,
              icon: const Icon(Icons.calendar_today),
              label: Text(
                _payday == null
                    ? 'Kapan gajian?'
                    : 'Tanggal gajian: ${shortDateLabel(_payday!)}',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Jatah harian dihitung sampai tanggal ini.',
              style: TextStyle(fontSize: 12),
            ),
          ] else ...[
            const SizedBox(height: 12),
            const Text(
              'Hitungannya sampai awal bulan. Tiap dapat uang, tambahkan '
              'lewat tombol Uang masuk di Dompet.',
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Simpan')),
        ],
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store});

  final Store store;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DompetScreen(store: widget.store),
          DashboardScreen(
            store: widget.store,
            onCheck: () => setState(() => _index = 0),
            onHistory: () => setState(() => _index = 3),
          ),
          BillsScreen(store: widget.store),
          HistoryScreen(store: widget.store),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search),
            selectedIcon: Icon(Icons.search),
            label: 'Cek',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Dompet',
          ),
          NavigationDestination(
            icon: Icon(Icons.savings_outlined),
            selectedIcon: Icon(Icons.savings),
            label: 'Tabungan',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Catatan',
          ),
        ],
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.store,
    required this.onCheck,
    required this.onHistory,
  });

  final Store store;
  final VoidCallback onCheck;
  final VoidCallback onHistory;

  Future<void> _addIncome(BuildContext context) async {
    final entry = await showDialog<_AmountResult>(
      context: context,
      builder: (_) =>
          const _AmountDialog(title: 'Uang masuk', label: 'Jumlah', initial: 0),
    );
    if (entry != null && entry.amount > 0) await store.addIncome(entry.amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dompet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Ubah isian',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SetupScreen(store: store, canCancel: true),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Saldo', style: theme.textTheme.labelLarge),
                      ),
                      if (!store.fixedIncome)
                        TextButton.icon(
                          onPressed: () => _addIncome(context),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Uang masuk'),
                        ),
                    ],
                  ),
                  Text(
                    money(store.balance),
                    style: theme.textTheme.displaySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'bisa dipakai ${money(store.spendableNow)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Jatah harian', style: theme.textTheme.labelLarge),
                  Text(
                    money(store.jatahNow),
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Saldonya turun otomatis sesuai jatah.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: store.fixedIncome ? 'Gajian' : 'Awal bulan',
                  value: '${store.days} hari lagi',
                  caption: store.fixedIncome
                      ? 'gajian ${shortDateLabel(store.payday!)}'
                      : 'sampai ${shortDateLabel(store.payday!)}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Stat(
                  label: 'Tabungan',
                  value: money(store.savings),
                  caption: 'nggak ikut jatah',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Catatan terakhir',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: onHistory,
                child: const Text('Lihat semua'),
              ),
            ],
          ),
          if (store.history.isEmpty)
            const Text('Belum ada catatan.')
          else
            for (final c in store.history.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _HistoryTile(check: c, onTap: onHistory),
              ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onCheck,
            icon: const Icon(Icons.price_check),
            label: const Text('Mau beli?'),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.caption,
  });

  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(caption, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class DompetScreen extends StatefulWidget {
  const DompetScreen({super.key, required this.store});

  final Store store;

  @override
  State<DompetScreen> createState() => _DompetScreenState();
}

class _Item {
  final name = TextEditingController();
  final amount = TextEditingController();

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

class _DompetScreenState extends State<DompetScreen> {
  final List<_Item> _items = [_Item()];
  final _scroll = ScrollController();
  String _kind = 'perlu';
  CheckResult? _result;

  @override
  void dispose() {
    _scroll.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  double get _total =>
      _items.map((i) => parseAmount(i.amount.text)).fold(0.0, (a, b) => a + b);

  String? get _itemsText {
    final parts = <String>[];
    var named = false;
    for (final i in _items) {
      final amount = parseAmount(i.amount.text);
      if (amount <= 0) continue;
      final name = i.name.text.trim();
      if (name.isNotEmpty) named = true;
      parts.add(name.isEmpty ? money(amount) : '$name ${money(amount)}');
    }
    if (parts.isEmpty || (parts.length == 1 && !named)) return null;
    return parts.join(', ');
  }

  // The row's TextField is still mounted this frame; dispose after it unmounts.
  void _retire(_Item item) {
    _items.remove(item);
    WidgetsBinding.instance.addPostFrameCallback((_) => item.dispose());
  }

  void _clearForm() {
    _items.first.name.clear();
    _items.first.amount.clear();
    while (_items.length > 1) {
      _retire(_items.last);
    }
    _kind = 'perlu';
    _result = null;
  }

  void _check() {
    final total = _total;
    if (total <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Isi harganya dulu ya.')));
      return;
    }
    setState(
      () => _result = checkPurchase(
        cost: total,
        spendable: widget.store.spendableNow,
        daysLeft: widget.store.days,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _record({required bool bought}) async {
    final result = _result!;
    await widget.store.addCheck(
      CheckRecord(
        time: DateTime.now(),
        cost: result.cost,
        items: _itemsText,
        kind: _kind,
        actual: bought,
        result: result,
      ),
    );
    if (!mounted) return;
    final id = widget.store.history.first.id;
    setState(_clearForm);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(bought ? 'Pembelian dicatat.' : 'Disimpan di Catatan.'),
        action: bought && id != null
            ? SnackBarAction(
                label: 'Batalkan',
                onPressed: () => widget.store.deleteCheck(id),
              )
            : null,
      ),
    );
  }

  Future<void> _editBalance() async {
    final edit = await showDialog<_BalanceEdit>(
      context: context,
      builder: (_) => _BalancePaydayDialog(
        initialBalance: widget.store.balance,
        payday: widget.store.payday!,
        fixedIncome: widget.store.fixedIncome,
      ),
    );
    if (edit == null) return;
    await widget.store.saveSettings(
      balance: edit.balance,
      bills: widget.store.bills,
      savings: widget.store.savings,
      payday: edit.payday,
      resetDecay: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Cek')),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Uang sekarang',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _editBalance,
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Perbarui'),
                      ),
                    ],
                  ),
                  Text(
                    money(widget.store.balance),
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Jatah harian ${money(widget.store.jatahNow)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    widget.store.fixedIncome
                        ? '${widget.store.days} hari lagi gajian'
                        : '${widget.store.days} hari sampai awal bulan',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Catat pembelian di luar jatah harian. Belanja harian sudah '
            'otomatis dihitung.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _items[i].name,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Beli apa?',
                        hintText: 'boleh kosong',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: _items[i].amount,
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                      onChanged: (_) => setState(() => _result = null),
                      decoration: const InputDecoration(
                        labelText: 'Harga',
                        prefixText: 'Rp ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  if (_items.length > 1)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => setState(() => _retire(_items[i])),
                    ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _items.add(_Item())),
              icon: const Icon(Icons.add),
              label: const Text('Tambah'),
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            expandedInsets: EdgeInsets.zero,
            segments: const [
              ButtonSegment(value: 'perlu', label: Text('Perlu')),
              ButtonSegment(value: 'pengen', label: Text('Pengen')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 8),
          Text('Total: ${money(_total)}', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          if (_result == null)
            FilledButton(onPressed: _check, child: const Text('Cek'))
          else ...[
            _ResultCard(result: _result!),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _record(bought: true),
                    child: const Text('Beli'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _record(bought: false),
                    child: const Text('Pikir-pikir'),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => setState(_clearForm),
              child: const Text('Batal'),
            ),
          ],
        ],
      ),
    );
  }
}

typedef _AmountResult = ({double amount, String title});

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    required this.label,
    required this.initial,
    this.titleLabel,
  });

  final String title;
  final String label;
  final double initial;
  final String? titleLabel;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final TextEditingController _controller;
  TextEditingController? _title;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: amountText(widget.initial));
    _title = widget.titleLabel == null ? null : TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    _title?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
            decoration: InputDecoration(
              labelText: widget.label,
              prefixText: 'Rp ',
              border: const OutlineInputBorder(),
            ),
          ),
          if (_title != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: widget.titleLabel,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((
            amount: parseAmount(_controller.text),
            title: _title?.text.trim() ?? '',
          )),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

class _BalanceEdit {
  const _BalanceEdit({required this.balance, required this.payday});

  final double balance;
  final DateTime payday;
}

class _BalancePaydayDialog extends StatefulWidget {
  const _BalancePaydayDialog({
    required this.initialBalance,
    required this.payday,
    required this.fixedIncome,
  });

  final double initialBalance;
  final DateTime payday;
  final bool fixedIncome;

  @override
  State<_BalancePaydayDialog> createState() => _BalancePaydayDialogState();
}

class _BalancePaydayDialogState extends State<_BalancePaydayDialog> {
  late final TextEditingController _controller;
  late DateTime _payday;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: amountText(widget.initialBalance),
    );
    _payday = widget.payday;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickPayday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _payday,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _payday = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Perbarui saldo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Uang asli sekarang',
              prefixText: 'Rp ',
              border: OutlineInputBorder(),
            ),
          ),
          if (widget.fixedIncome) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickPayday,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('Gajian: ${shortDateLabel(_payday)}'),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _BalanceEdit(
              balance: parseAmount(_controller.text),
              payday: _payday,
            ),
          ),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final CheckResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final good = result.affordable;
    final color = good ? Colors.green.shade700 : theme.colorScheme.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  good ? Icons.check_circle : Icons.error,
                  color: color,
                  size: 26,
                ),
                const SizedBox(width: 8),
                Text(
                  good ? 'Aman' : 'Nggak aman',
                  style: theme.textTheme.headlineSmall?.copyWith(color: color),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Sisa bisa dipakai',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              money(result.afterSpendable),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 4),
            _Metric(
              label: 'Jatah harian',
              value: money(result.dailyAfter),
              note: percent(result.percentChange),
            ),
            if (result.dailyBefore > result.dailyAfter) ...[
              const SizedBox(height: 8),
              Text(
                'Jatah harian turun '
                '${money(result.dailyBefore - result.dailyAfter)} per hari '
                'sampai gajian.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.note});

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                if (note != null)
                  Text(
                    note!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class BillsScreen extends StatelessWidget {
  const BillsScreen({super.key, required this.store});

  final Store store;

  Future<void> _editSavings(BuildContext context, {required bool add}) async {
    final entry = await showDialog<_AmountResult>(
      context: context,
      builder: (_) => _AmountDialog(
        title: add ? 'Tambah tabungan' : 'Tarik tabungan',
        label: add ? 'Dari saldo' : 'Buat dipakai',
        initial: 0,
        titleLabel: 'Buat apa? (opsional)',
      ),
    );
    if (entry == null || entry.amount <= 0) return;
    final moved = add
        ? await store.addSavings(entry.amount, title: entry.title)
        : await store.withdrawSavings(entry.amount, title: entry.title);
    if (!context.mounted || moved >= entry.amount) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cuma ${money(moved)} yang bisa dipindah.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Tabungan')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tabungan', style: theme.textTheme.labelLarge),
                  Text(
                    money(store.savings),
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tambah/Tarik manual dari saldo.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _editSavings(context, add: true),
                          icon: const Icon(Icons.add),
                          label: const Text('Tambah'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _editSavings(context, add: false),
                          icon: const Icon(Icons.remove),
                          label: const Text('Tarik'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Uang tabungan nggak ikut dihitung buat jajan.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: const Text('Simulasi nabung'),
              subtitle: const Text('Berapa yang bisa ditabung tiap gajian?'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SimulationScreen(
                    payday: store.payday,
                    fixedIncome: store.fixedIncome,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Riwayat', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (store.savingsLog.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Belum ada riwayat tabungan.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final entry in store.savingsLog)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SavingsTile(
                  entry: entry,
                  onDelete: () => _deleteSavingsEntry(context, store, entry),
                ),
              ),
        ],
      ),
    );
  }
}

class _SavingsTile extends StatelessWidget {
  const _SavingsTile({required this.entry, this.onDelete});

  final SavingsEntry entry;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final up = entry.amount > 0;
    return Card(
      child: ListTile(
        title: Text(entry.title),
        subtitle: Text(timeLabel(entry.time)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${up ? '+' : ''}${money(entry.amount)}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: up ? Colors.green.shade700 : theme.colorScheme.error,
              ),
            ),
            if (onDelete != null)
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Hapus',
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}

class SimulationScreen extends StatefulWidget {
  const SimulationScreen({super.key, this.payday, this.fixedIncome = true});

  final DateTime? payday;
  final bool fixedIncome;

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen> {
  final _income = TextEditingController();
  late DateTime _payday;
  double _rate = 0.2;
  late int _targetMonths;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _payday =
        widget.payday ?? nextMonthly(DateTime(now.year, now.month, now.day));
    _targetMonths = widget.fixedIncome ? 6 : 12;
  }

  @override
  void dispose() {
    _income.dispose();
    super.dispose();
  }

  Future<void> _pickPayday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _payday,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _payday = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = simulateSaving(
      income: parseAmount(_income.text),
      days: daysLeft(_payday, DateTime.now()),
      rate: _rate,
      targetMonths: _targetMonths,
    );
    final months = plan.target <= 0 ? null : plan.monthsToTarget;
    return Scaffold(
      appBar: AppBar(title: const Text('Simulasi nabung')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              widget.fixedIncome
                  ? 'Nabung dulu tiap gajian, baru pakai sisanya. '
                        'Dana darurat aman di 3–6 kali biaya hidup.'
                  : 'Pemasukan nggak tetap? Pakai angka paling kecil bulan '
                        'ini. Dana darurat aman di 6–12 kali biaya hidup.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _income,
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: widget.fixedIncome
                  ? 'Uang masuk per bulan'
                  : 'Uang masuk bulan ini',
              prefixText: 'Rp ',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickPayday,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(
              '${widget.fixedIncome ? 'Gajian' : 'Awal bulan'}: '
              '${shortDateLabel(_payday)}',
            ),
          ),
          const SizedBox(height: 16),
          Text('Nabung tiap gajian', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<double>(
            expandedInsets: EdgeInsets.zero,
            segments: const [
              ButtonSegment(value: 0.1, label: Text('10%')),
              ButtonSegment(value: 0.2, label: Text('20%')),
              ButtonSegment(value: 0.3, label: Text('30%')),
            ],
            selected: {_rate},
            onSelectionChanged: (s) => setState(() => _rate = s.first),
          ),
          const SizedBox(height: 16),
          Text('Target dana darurat', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            expandedInsets: EdgeInsets.zero,
            segments: const [
              ButtonSegment(value: 3, label: Text('3×')),
              ButtonSegment(value: 6, label: Text('6×')),
              ButtonSegment(value: 12, label: Text('12×')),
            ],
            selected: {_targetMonths},
            onSelectionChanged: (s) => setState(() => _targetMonths = s.first),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _Metric(label: 'Dana darurat', value: money(plan.target)),
                  _Metric(
                    label: widget.fixedIncome
                        ? 'Nabung tiap gajian'
                        : 'Nabung tiap bulan',
                    value: money(plan.perPayday),
                  ),
                  _Metric(
                    label: 'Biaya hidup per bulan',
                    value: money(plan.livingCost),
                  ),
                  _Metric(label: 'Jatah harian', value: money(plan.daily)),
                  _Metric(
                    label: 'Target tercapai',
                    value: months == null ? '—' : '~$months bulan',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Proyeksi tabungan', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (var i = 0; i < plan.projections.length; i++)
                    _Metric(
                      label: '${i + 1} tahun',
                      value: money(plan.projections[i]),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.store});

  final Store store;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = widget.store;
    final install = store.installDate;
    final rows = historyEntries(store.history, store.savingsLog, _filter);
    final totals = kindTotals(store.history);
    return Scaffold(
      appBar: AppBar(title: const Text('Catatan')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Semua'),
                selected: _filter == null,
                onSelected: (_) => setState(() => _filter = null),
              ),
              ChoiceChip(
                label: const Text('Perlu'),
                selected: _filter == 'perlu',
                onSelected: (_) => setState(() => _filter = 'perlu'),
              ),
              ChoiceChip(
                label: const Text('Pengen'),
                selected: _filter == 'pengen',
                onSelected: (_) => setState(() => _filter = 'pengen'),
              ),
              ChoiceChip(
                label: const Text('Tabungan'),
                selected: _filter == 'tabungan',
                onSelected: (_) => setState(() => _filter = 'tabungan'),
              ),
            ],
          ),
          if (totals.isNotEmpty && _filter != 'tabungan') ...[
            const SizedBox(height: 12),
            Text(
              'Total: Perlu ${money(totals['perlu'] ?? 0)} · '
              'Pengen ${money(totals['pengen'] ?? 0)}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(
              store.history.isEmpty && store.savingsLog.isEmpty
                  ? 'Belum ada catatan. '
                        '${install == null ? '' : 'Dilacak sejak ${dateLabel(install)}.'}'
                  : 'Belum ada yang cocok.',
            )
          else
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: switch (row) {
                  CheckRecord() => _HistoryTile(check: row),
                  SavingsEntry() => _SavingsTile(
                    entry: row,
                    onDelete: () => _deleteSavingsEntry(context, store, row),
                  ),
                  _ => const SizedBox.shrink(),
                },
              ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.check, this.onTap});

  final CheckRecord check;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final good = check.result.affordable;
    final label = kindLabels[check.kind];
    final action = check.actual ? 'Dibeli' : 'Cek';
    final lines = [
      if (check.items != null) check.items!,
      '${timeLabel(check.time)} · $action${label == null ? '' : ' · $label'}',
      'bisa dipakai ${money(check.result.beforeSpendable)} → '
          '${money(check.result.afterSpendable)}',
    ];
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(
          '${money(check.cost)}  ·  ${good ? 'Aman' : 'Nggak aman'}',
          style: TextStyle(
            color: good ? Colors.green.shade700 : theme.colorScheme.error,
          ),
        ),
        subtitle: Text(lines.join('\n')),
        isThreeLine: lines.length > 2,
      ),
    );
  }
}
