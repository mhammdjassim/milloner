// main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app_database.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DailyExpensesApp());
}

class DailyExpensesApp extends StatelessWidget {
  const DailyExpensesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مصروفي اليومي',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff176b5d),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff4f7f5),
        fontFamily: 'Arial',
        useMaterial3: true,
      ),
      home: const DailyExpensesPage(),
    );
  }
}

class MoneyEntry {
  const MoneyEntry({
    required this.title,
    required this.amount,
    required this.type,
    required this.currency,
    required this.dateTime,
  });

  final String title;
  final double amount;
  final EntryType type;
  final MoneyCurrency currency;
  final DateTime dateTime;

  Map<String, dynamic> toJson() => {
    'title': title,
    'amount': amount,
    'type': type.name,
    'currency': currency.name,
    'dateTime': dateTime.toIso8601String(),
  };

  factory MoneyEntry.fromJson(Map<String, dynamic> json) => MoneyEntry(
    title: json['title'] as String,
    amount: (json['amount'] as num).toDouble(),
    type: EntryType.values.byName(json['type'] as String),
    currency: MoneyCurrency.values.byName(
      json['currency'] as String? ?? MoneyCurrency.iqd.name,
    ),
    dateTime: DateTime.parse(json['dateTime'] as String),
  );
}

enum EntryType { income, expense }

enum DebtDirection { owedToMe, iOwe }

enum MoneyCurrency { iqd, usd }

extension MoneyCurrencyDetails on MoneyCurrency {
  String get label => switch (this) {
    MoneyCurrency.iqd => 'الدينار العراقي',
    MoneyCurrency.usd => 'الدولار الأمريكي',
  };

  String get symbol => switch (this) {
    MoneyCurrency.iqd => 'د.ع',
    MoneyCurrency.usd => '\$',
  };

  String get code => switch (this) {
    MoneyCurrency.iqd => 'IQD',
    MoneyCurrency.usd => 'USD',
  };
}

enum ReportPeriod { daily, monthly, yearly }

class IncomeGoal {
  const IncomeGoal({
    required this.amount,
    required this.currency,
    required this.start,
    required this.end,
  });

  final double amount;
  final MoneyCurrency currency;
  final DateTime start;
  final DateTime end;

  Map<String, dynamic> toJson() => {
    'amount': amount,
    'currency': currency.name,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
  };

  factory IncomeGoal.fromJson(Map<String, dynamic> json) => IncomeGoal(
    amount: (json['amount'] as num).toDouble(),
    currency: MoneyCurrency.values.byName(
      json['currency'] as String? ?? MoneyCurrency.iqd.name,
    ),
    start: DateTime.parse(json['start'] as String),
    end: DateTime.parse(json['end'] as String),
  );
}

class DebtRecord {
  const DebtRecord({
    required this.person,
    required this.amount,
    required this.currency,
    required this.direction,
    required this.dateTime,
    this.paidAmount = 0,
  });

  final String person;
  final double amount;
  final MoneyCurrency currency;
  final DebtDirection direction;
  final DateTime dateTime;
  final double paidAmount;

  double get remainingAmount => (amount - paidAmount).clamp(0, double.infinity);

  double get excessAmount => (paidAmount - amount).clamp(0, double.infinity);

  bool get isSettled => remainingAmount == 0;

  Map<String, dynamic> toJson() => {
    'person': person,
    'amount': amount,
    'currency': currency.name,
    'direction': direction.name,
    'dateTime': dateTime.toIso8601String(),
    'paidAmount': paidAmount,
  };

  factory DebtRecord.fromJson(Map<String, dynamic> json) => DebtRecord(
    person: json['person'] as String,
    amount: (json['amount'] as num).toDouble(),
    currency: MoneyCurrency.values.byName(
      json['currency'] as String? ?? MoneyCurrency.iqd.name,
    ),
    direction: DebtDirection.values.byName(
      json['direction'] as String? ?? DebtDirection.owedToMe.name,
    ),
    dateTime: DateTime.parse(json['dateTime'] as String),
    paidAmount:
        (json['paidAmount'] as num?)?.toDouble() ??
        ((json['isSettled'] as bool? ?? false)
            ? (json['amount'] as num).toDouble()
            : 0),
  );
}

class DailyExpensesPage extends StatefulWidget {
  const DailyExpensesPage({super.key});

  @override
  State<DailyExpensesPage> createState() => _DailyExpensesPageState();
}

class _DailyExpensesPageState extends State<DailyExpensesPage> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final List<MoneyEntry> _entries = [];
  EntryType _entryType = EntryType.expense;
  MoneyCurrency _entryCurrency = MoneyCurrency.iqd;
  MoneyCurrency _displayCurrency = MoneyCurrency.iqd;
  int _selectedTab = 0;
  ReportPeriod _reportPeriod = ReportPeriod.daily;
  IncomeGoal? _incomeGoal;
  bool _isLoadingData = true;
  Object? _dataLoadError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoadingData = true;
        _dataLoadError = null;
      });
    }
    try {
      final settings = await AppDatabase.loadSettings();
      final savedEntries = await AppDatabase.loadEntries();
      final entries = savedEntries.map(
        (entry) => MoneyEntry(
          title: entry['title']! as String,
          amount: (entry['amount']! as num).toDouble(),
          type: EntryType.values.byName(entry['type']! as String),
          currency: MoneyCurrency.values.byName(entry['currency']! as String),
          dateTime: DateTime.parse(entry['dateTime']! as String),
        ),
      );
      final savedGoal = settings['income_goal'];
      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(entries);
        _displayCurrency = MoneyCurrency.values.byName(
          settings['display_currency'] ?? MoneyCurrency.iqd.name,
        );
        _entryCurrency = MoneyCurrency.values.byName(
          settings['entry_currency'] ?? MoneyCurrency.iqd.name,
        );
        _incomeGoal = savedGoal == null
            ? null
            : IncomeGoal.fromJson(
                jsonDecode(savedGoal) as Map<String, dynamic>,
              );
        _isLoadingData = false;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _dataLoadError = error;
        _isLoadingData = false;
      });
      _reportStorageError(error, stackTrace);
    }
  }

  Future<void> _saveData() async {
    if (_isLoadingData || _dataLoadError != null) return;
    try {
      await AppDatabase.saveAppData(
        entries: _entries
            .map(
              (entry) => {
                'title': entry.title,
                'amount': entry.amount,
                'type': entry.type.name,
                'currency': entry.currency.name,
                'dateTime': entry.dateTime.toIso8601String(),
              },
            )
            .toList(),
        settings: {
          'display_currency': _displayCurrency.name,
          'entry_currency': _entryCurrency.name,
          'income_goal': _incomeGoal == null
              ? null
              : jsonEncode(_incomeGoal!.toJson()),
        },
      );
    } catch (error, stackTrace) {
      _reportStorageError(error, stackTrace);
    }
  }

  void _reportStorageError(Object error, StackTrace stackTrace) {
    debugPrint('SQLite storage error: $error');
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'SQLite storage',
        context: ErrorDescription('while reading or writing app data'),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ البيانات. حاول مرة أخرى.')),
      );
    }
  }

  double get _totalIncome => _entries
      .where(
        (entry) =>
            entry.type == EntryType.income &&
            entry.currency == _displayCurrency,
      )
      .fold(0, (sum, entry) => sum + entry.amount);

  double get _totalExpenses => _entries
      .where(
        (entry) =>
            entry.type == EntryType.expense &&
            entry.currency == _displayCurrency,
      )
      .fold(0, (sum, entry) => sum + entry.amount);

  double get _goalIncome {
    final goal = _incomeGoal;
    if (goal == null) return 0;
    final start = DateTime(goal.start.year, goal.start.month, goal.start.day);
    final end = DateTime(
      goal.end.year,
      goal.end.month,
      goal.end.day,
      23,
      59,
      59,
    );
    return _entries
        .where(
          (entry) =>
              entry.type == EntryType.income &&
              entry.currency == goal.currency &&
              !entry.dateTime.isBefore(start) &&
              !entry.dateTime.isAfter(end),
        )
        .fold(0, (sum, entry) => sum + entry.amount);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _addEntry() {
    final title = _titleController.text.trim();
    final amount = double.tryParse(
      _amountController.text.trim().replaceAll(',', '.'),
    );
    if (title.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل الوصف ومبلغًا صحيحًا')),
      );
      return;
    }

    setState(() {
      _entries.insert(
        0,
        MoneyEntry(
          title: title,
          amount: amount,
          type: _entryType,
          currency: _entryCurrency,
          dateTime: DateTime.now(),
        ),
      );
      _titleController.clear();
      _amountController.clear();
    });
    _saveData();
    FocusScope.of(context).unfocus();
  }

  Future<void> _confirmRemoveEntry(int index) async {
    final entry = _entries[index];
    final typeLabel = entry.type == EntryType.income ? 'الدخل' : 'المصروف';
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد حذف العملية'),
        content: Text(
          'هل أنت متأكد من حذف $typeLabel "${entry.title}" بمبلغ ${_formatAmount(entry.amount)} ${entry.currency.symbol}؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;
    setState(() => _entries.removeAt(index));
    _saveData();
  }

  String _formatAmount(double amount) {
    final hasDecimals = amount % 1 != 0;
    return hasDecimals ? amount.toStringAsFixed(2) : amount.toStringAsFixed(0);
  }

  String _formatDate(DateTime date) =>
      '${date.day}/${date.month}/${date.year} - ${_formatTime(date)}';

  String _formatTime(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour < 12 ? 'ص' : 'م';
    return '$hour:$minute $period';
  }

  String _formatDateOnly(DateTime date) =>
      '${date.day}/${date.month}/${date.year}';

  List<MoneyEntry> get _periodEntries {
    final now = DateTime.now();
    return _entries.where((entry) {
      switch (_reportPeriod) {
        case ReportPeriod.daily:
          return entry.dateTime.year == now.year &&
              entry.dateTime.month == now.month &&
              entry.dateTime.day == now.day;
        case ReportPeriod.monthly:
          return entry.dateTime.year == now.year &&
              entry.dateTime.month == now.month;
        case ReportPeriod.yearly:
          return entry.dateTime.year == now.year;
      }
    }).toList();
  }

  double _sumEntries(List<MoneyEntry> entries, EntryType type) => entries
      .where(
        (entry) => entry.type == type && entry.currency == _displayCurrency,
      )
      .fold(0, (sum, entry) => sum + entry.amount);

  List<_TopEntry> _topEntries(List<MoneyEntry> entries, EntryType type) {
    final totals = <String, double>{};
    for (final entry in entries.where(
      (entry) => entry.type == type && entry.currency == _displayCurrency,
    )) {
      totals.update(
        entry.title,
        (amount) => amount + entry.amount,
        ifAbsent: () => entry.amount,
      );
    }
    final result =
        totals.entries
            .map((entry) => _TopEntry(title: entry.key, amount: entry.value))
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));
    return result.take(5).toList();
  }

  List<_ChartBucket> _chartBuckets(List<MoneyEntry> entries) {
    final count = switch (_reportPeriod) {
      ReportPeriod.daily => 6,
      ReportPeriod.monthly => 6,
      ReportPeriod.yearly => 12,
    };
    final labels = switch (_reportPeriod) {
      ReportPeriod.daily => ['00', '04', '08', '12', '16', '20'],
      ReportPeriod.monthly => ['1', '6', '11', '16', '21', '26'],
      ReportPeriod.yearly => List.generate(12, (index) => '${index + 1}'),
    };
    final buckets = List.generate(
      count,
      (index) => _ChartBucket(label: labels[index]),
    );

    for (final entry in entries.where(
      (entry) => entry.currency == _displayCurrency,
    )) {
      final index = switch (_reportPeriod) {
        ReportPeriod.daily => entry.dateTime.hour ~/ 4,
        ReportPeriod.monthly => ((entry.dateTime.day - 1) ~/ 5).clamp(0, 5),
        ReportPeriod.yearly => entry.dateTime.month - 1,
      };
      if (index < 0 || index >= count) continue;
      if (entry.type == EntryType.income) {
        buckets[index].income += entry.amount;
      } else {
        buckets[index].expense += entry.amount;
      }
    }
    return buckets;
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          leading: PopupMenuButton<String>(
            tooltip: 'القائمة',
            icon: const Icon(Icons.menu),
            onSelected: _onMenuSelected,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('الإعدادات'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'about',
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('حول التطبيق'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'backup',
                child: ListTile(
                  leading: Icon(Icons.backup_outlined),
                  title: Text('نسخ احتياطي للبيانات'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          centerTitle: false,
          backgroundColor: Colors.transparent,
          title: Text(switch (_selectedTab) {
            1 => 'الديون',
            2 => 'التقارير',
            3 => 'محول العملات',
            _ => 'مصروفي اليومي',
          }, style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: _selectedTab == 0
              ? [
                  IconButton(
                    onPressed: _showSetIncomeGoal,
                    tooltip: 'تحديد هدف الدخل',
                    icon: const Icon(Icons.flag_outlined),
                  ),
                ]
              : null,
        ),
        body: SafeArea(
          child: _isLoadingData
              ? const Center(child: Text('جار تحميل البيانات...'))
              : _dataLoadError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('تعذر تحميل البيانات المحفوظة'),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _loadData,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : switch (_selectedTab) {
                  0 => _buildHome(today),
                  1 => const _DebtRegisterPage(),
                  2 => _buildReports(),
                  _ => const _CurrencyConverter(),
                },
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedTab,
          onDestinationSelected: (index) =>
              setState(() => _selectedTab = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'الرئيسية',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'الديون',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: 'التقارير',
            ),
            NavigationDestination(
              icon: Icon(Icons.currency_exchange_outlined),
              selectedIcon: Icon(Icons.currency_exchange),
              label: 'تحويل العملات',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHome(DateTime today) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          'الدخل والمصروفات',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: const Color(0xff173c36),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _formatDateOnly(today),
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 20),
        _BalanceCard(
          income: _totalIncome,
          expenses: _totalExpenses,
          currency: _displayCurrency,
          formatAmount: _formatAmount,
        ),
        const SizedBox(height: 12),
        _CurrencySelector(
          label: 'عملة عرض الملخص',
          value: _displayCurrency,
          onChanged: (currency) {
            setState(() => _displayCurrency = currency);
            _saveData();
          },
        ),
        const SizedBox(height: 14),
        _IncomeGoalCard(
          goal: _incomeGoal,
          achieved: _goalIncome,
          formatAmount: _formatAmount,
          formatDate: _formatDateOnly,
          onSetGoal: _showSetIncomeGoal,
        ),
        const SizedBox(height: 20),
        _EntryForm(
          type: _entryType,
          currency: _entryCurrency,
          titleController: _titleController,
          amountController: _amountController,
          onTypeChanged: (type) => setState(() => _entryType = type),
          onCurrencyChanged: (currency) => setState(() {
            _entryCurrency = currency;
            _saveData();
          }),
          onSubmit: _addEntry,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'سجل العمليات',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            Text(
              '${_entries.length} عملية',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_entries.isEmpty)
          const _EmptyEntries()
        else
          ..._entries.asMap().entries.map(
            (entry) => _EntryTile(
              entry: entry.value,
              amount: _formatAmount(entry.value.amount),
              currency: entry.value.currency,
              date: _formatDate(entry.value.dateTime),
              onDelete: () => _confirmRemoveEntry(entry.key),
            ),
          ),
        const SizedBox(height: 18),
        if (_entries.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => _showFinalReport(context),
            icon: const Icon(Icons.assessment_outlined),
            label: const Text('عرض التقرير النهائي لليوم'),
          ),
      ],
    );
  }

  Widget _buildReports() {
    final entries = _periodEntries;
    final income = _sumEntries(entries, EntryType.income);
    final expenses = _sumEntries(entries, EntryType.expense);
    final topIncome = _topEntries(entries, EntryType.income);
    final topExpenses = _topEntries(entries, EntryType.expense);
    final periodLabel = switch (_reportPeriod) {
      ReportPeriod.daily => 'اليوم',
      ReportPeriod.monthly => 'هذا الشهر',
      ReportPeriod.yearly => 'هذه السنة',
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          'التقارير',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: const Color(0xff173c36),
          ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<ReportPeriod>(
          segments: const [
            ButtonSegment(value: ReportPeriod.daily, label: Text('يومي')),
            ButtonSegment(value: ReportPeriod.monthly, label: Text('شهري')),
            ButtonSegment(value: ReportPeriod.yearly, label: Text('سنوي')),
          ],
          selected: {_reportPeriod},
          onSelectionChanged: (selection) =>
              setState(() => _reportPeriod = selection.first),
        ),
        const SizedBox(height: 12),
        _CurrencySelector(
          label: 'عملة التقرير',
          value: _displayCurrency,
          onChanged: (currency) {
            setState(() => _displayCurrency = currency);
            _saveData();
          },
        ),
        const SizedBox(height: 16),
        _ReportSummary(
          period: periodLabel,
          income: income,
          expenses: expenses,
          currency: _displayCurrency,
          formatAmount: _formatAmount,
        ),
        const SizedBox(height: 16),
        _ReportChart(
          buckets: _chartBuckets(entries),
          currency: _displayCurrency,
          formatAmount: _formatAmount,
        ),
        const SizedBox(height: 18),
        _TopEntriesSection(
          title: 'أكثر مصادر الدخل',
          emptyText: 'لا يوجد دخل مسجل ضمن هذه الفترة',
          entries: topIncome,
          currency: _displayCurrency,
          color: const Color(0xff176b5d),
          icon: Icons.trending_up,
          formatAmount: _formatAmount,
        ),
        const SizedBox(height: 12),
        _TopEntriesSection(
          title: 'أعلى المصروفات',
          emptyText: 'لا توجد مصروفات مسجلة ضمن هذه الفترة',
          entries: topExpenses,
          currency: _displayCurrency,
          color: const Color(0xffbd5147),
          icon: Icons.trending_down,
          formatAmount: _formatAmount,
        ),
      ],
    );
  }

  void _showSetIncomeGoal() {
    var enteredAmount = _incomeGoal == null
        ? ''
        : _formatAmount(_incomeGoal!.amount);
    var goalCurrency = _incomeGoal?.currency ?? _displayCurrency;
    var start = _incomeGoal?.start ?? DateTime.now();
    var end = _incomeGoal?.end ?? DateTime.now().add(const Duration(days: 6));

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('هدف الدخل خلال مدة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                onChanged: (value) => enteredAmount = value,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'المبلغ المطلوب تحقيقه',
                  hintText: 'مثال: 50000',
                  suffixText: goalCurrency.symbol,
                ),
              ),
              const SizedBox(height: 14),
              _CurrencySelector(
                label: 'عملة الهدف',
                value: goalCurrency,
                onChanged: (currency) =>
                    setDialogState(() => goalCurrency = currency),
              ),
              const SizedBox(height: 8),
              _DateButton(
                label: 'من تاريخ ${_formatDateOnly(start)}',
                onPressed: () async {
                  final selected = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    initialDate: start,
                  );
                  if (selected != null) setDialogState(() => start = selected);
                },
              ),
              _DateButton(
                label: 'إلى تاريخ ${_formatDateOnly(end)}',
                onPressed: () async {
                  final selected = await showDatePicker(
                    context: context,
                    firstDate: start,
                    lastDate: DateTime(2100),
                    initialDate: end.isBefore(start) ? start : end,
                  );
                  if (selected != null) setDialogState(() => end = selected);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(
                  enteredAmount.trim().replaceAll(',', '.'),
                );
                if (amount == null || amount <= 0 || end.isBefore(start)) {
                  return;
                }
                setState(
                  () => _incomeGoal = IncomeGoal(
                    amount: amount,
                    currency: goalCurrency,
                    start: start,
                    end: end,
                  ),
                );
                _saveData();
                Navigator.pop(dialogContext);
              },
              child: const Text('حفظ الهدف'),
            ),
          ],
        ),
      ),
    );
  }

  void _onMenuSelected(String action) {
    switch (action) {
      case 'settings':
        unawaited(_showSettings());
      case 'about':
        showAboutDialog(
          context: context,
          applicationName: 'مصروفي اليومي',
          applicationVersion: '1.0.0',
          children: const [
            Text('تطبيق مليونير وهو الادارة الدخل  والمصاريف \n '' والديون . \n ' ' مطور التطبيق الاستاذ محمد جاسم الغزالي .',textDirection: TextDirection.rtl ),
          ],
        );
      case 'backup':
        unawaited(_createBackup());
    }
  }

  Future<void> _showSettings() async {
    var displayCurrency = _displayCurrency;
    var entryCurrency = _entryCurrency;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('الإعدادات'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SettingsCurrencySelector(
                label: 'عملة عرض الملخص',
                value: displayCurrency,
                onChanged: (currency) =>
                    setDialogState(() => displayCurrency = currency),
              ),
              const SizedBox(height: 12),
              _SettingsCurrencySelector(
                label: 'العملة الافتراضية للعملية',
                value: entryCurrency,
                onChanged: (currency) =>
                    setDialogState(() => entryCurrency = currency),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                setState(() {
                  _displayCurrency = displayCurrency;
                  _entryCurrency = entryCurrency;
                });
                await _saveData();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createBackup() async {
    try {
      final backup = await AppDatabase.exportBackupJson();
      final now = DateTime.now();
      String twoDigits(int value) => value.toString().padLeft(2, '0');
      final fileName =
          'what_lose_backup_${now.year}${twoDigits(now.month)}'
          '${twoDigits(now.day)}_${twoDigits(now.hour)}'
          '${twoDigits(now.minute)}.json';
      final location = await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(backup)),
        mimeType: 'application/json',
        dialogTitle: 'حفظ نسخة احتياطية',
      );
      if (!mounted || location == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ النسخة الاحتياطية بنجاح')),
      );
    } catch (error, stackTrace) {
      debugPrint('SQLite backup error: $error');
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'SQLite backup',
          context: ErrorDescription('while exporting app data'),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إنشاء النسخة الاحتياطية')),
      );
    }
  }

  void _showFinalReport(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('التقرير النهائي لليوم'),
        content: Text(
          'إجمالي الدخل: ${_formatAmount(_totalIncome)} ${_displayCurrency.symbol}\nإجمالي المصروفات: ${_formatAmount(_totalExpenses)} ${_displayCurrency.symbol}\nالصافي: ${_formatAmount(_totalIncome - _totalExpenses)} ${_displayCurrency.symbol}\n\nعدد العمليات: ${_entries.where((entry) => entry.currency == _displayCurrency).length}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            height: 1.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}

class _DebtRegisterPage extends StatefulWidget {
  const _DebtRegisterPage();

  @override
  State<_DebtRegisterPage> createState() => _DebtRegisterPageState();
}

class _DebtRegisterPageState extends State<_DebtRegisterPage> {
  final _personController = TextEditingController();
  final _amountController = TextEditingController();
  final List<DebtRecord> _debts = [];
  MoneyCurrency _currency = MoneyCurrency.iqd;
  DebtDirection _direction = DebtDirection.owedToMe;
  bool _isLoadingDebts = true;
  Object? _debtLoadError;

  @override
  void initState() {
    super.initState();
    _loadDebts();
  }

  Future<void> _loadDebts() async {
    if (mounted) {
      setState(() {
        _isLoadingDebts = true;
        _debtLoadError = null;
      });
    }
    try {
      final savedDebts = await AppDatabase.loadDebts();
      final debts = savedDebts.map(
        (debt) => DebtRecord(
          person: debt['person']! as String,
          amount: (debt['amount']! as num).toDouble(),
          currency: MoneyCurrency.values.byName(debt['currency']! as String),
          direction: DebtDirection.values.byName(debt['direction']! as String),
          dateTime: DateTime.parse(debt['dateTime']! as String),
          paidAmount: (debt['paidAmount']! as num).toDouble(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _debts
          ..clear()
          ..addAll(debts);
        _isLoadingDebts = false;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _debtLoadError = error;
        _isLoadingDebts = false;
      });
      _reportStorageError(error, stackTrace);
    }
  }

  Future<void> _saveDebts() async {
    if (_isLoadingDebts || _debtLoadError != null) return;
    try {
      await AppDatabase.saveDebts(
        _debts
            .map(
              (debt) => {
                'person': debt.person,
                'amount': debt.amount,
                'currency': debt.currency.name,
                'direction': debt.direction.name,
                'dateTime': debt.dateTime.toIso8601String(),
                'paidAmount': debt.paidAmount,
              },
            )
            .toList(),
      );
    } catch (error, stackTrace) {
      _reportStorageError(error, stackTrace);
    }
  }

  void _reportStorageError(Object error, StackTrace stackTrace) {
    debugPrint('SQLite debt storage error: $error');
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'SQLite storage',
        context: ErrorDescription('while reading or writing debt records'),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ البيانات. حاول مرة أخرى.')),
      );
    }
  }

  void _addDebt() {
    final person = _personController.text.trim();
    final amount = double.tryParse(
      _amountController.text.trim().replaceAll(',', '.'),
    );
    if (person.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسم الشخص ومبلغًا صحيحًا')),
      );
      return;
    }

    setState(() {
      _debts.insert(
        0,
        DebtRecord(
          person: person,
          amount: amount,
          currency: _currency,
          direction: _direction,
          dateTime: DateTime.now(),
        ),
      );
      _personController.clear();
      _amountController.clear();
    });
    _saveDebts();
    FocusScope.of(context).unfocus();
  }

  void _recordPayment(int index) {
    final debt = _debts[index];
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _DebtPaymentDialog(
        debt: debt,
        formatAmount: _formatAmount,
        onSave: (payment) {
          setState(() {
            _debts[index] = DebtRecord(
              person: debt.person,
              amount: debt.amount,
              currency: debt.currency,
              direction: debt.direction,
              dateTime: debt.dateTime,
              paidAmount: debt.paidAmount + payment,
            );
          });
          _saveDebts();
          Navigator.pop(dialogContext);
        },
      ),
    );
  }

  Future<void> _confirmRemoveDebt(int index) async {
    final debt = _debts[index];
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد حذف الدين'),
        content: Text('هل تريد حذف الدين المسجل باسم ${debt.person}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;
    setState(() => _debts.removeAt(index));
    _saveDebts();
  }

  double _total(DebtDirection direction) => _debts
      .where(
        (debt) =>
            debt.direction == direction &&
            debt.currency == _currency &&
            debt.remainingAmount > 0,
      )
      .fold(0, (sum, debt) => sum + debt.remainingAmount);

  String _formatAmount(double amount) =>
      amount % 1 == 0 ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);

  @override
  void dispose() {
    _personController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingDebts) {
      return const Center(child: Text('جار تحميل سجل الديون...'));
    }
    if (_debtLoadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('تعذر تحميل سجل الديون'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _loadDebts,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        DropdownButtonFormField<MoneyCurrency>(
          initialValue: _currency,
          decoration: const InputDecoration(
            labelText: 'عملة عرض الملخص',
            border: OutlineInputBorder(),
          ),
          items: MoneyCurrency.values
              .map(
                (currency) => DropdownMenuItem(
                  value: currency,
                  child: Text('${currency.label} (${currency.code})'),
                ),
              )
              .toList(),
          onChanged: (currency) {
            if (currency != null) setState(() => _currency = currency);
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _DebtSummaryTile(
                label: 'مستحق لي',
                amount: _total(DebtDirection.owedToMe),
                currency: _currency,
                color: const Color(0xff21866f),
                formatAmount: _formatAmount,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DebtSummaryTile(
                label: 'مستحق عليّ',
                amount: _total(DebtDirection.iOwe),
                currency: _currency,
                color: const Color(0xffd66b5f),
                formatAmount: _formatAmount,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'تسجيل دين',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _personController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'اسم الشخص أو الجهة',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'المبلغ',
            prefixIcon: Icon(Icons.payments_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<DebtDirection>(
                initialValue: _direction,
                decoration: const InputDecoration(
                  labelText: 'اتجاه الدين',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: DebtDirection.owedToMe,
                    child: Text('لي عنده'),
                  ),
                  DropdownMenuItem(
                    value: DebtDirection.iOwe,
                    child: Text('عليّ له'),
                  ),
                ],
                onChanged: (direction) {
                  if (direction != null) {
                    setState(() => _direction = direction);
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<MoneyCurrency>(
                initialValue: _currency,
                decoration: const InputDecoration(
                  labelText: 'العملة',
                  border: OutlineInputBorder(),
                ),
                items: MoneyCurrency.values
                    .map(
                      (currency) => DropdownMenuItem(
                        value: currency,
                        child: Text(currency.code),
                      ),
                    )
                    .toList(),
                onChanged: (currency) {
                  if (currency != null) setState(() => _currency = currency);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _addDebt,
            icon: const Icon(Icons.add),
            label: const Text('حفظ الدين'),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'سجل الديون',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text('${_debts.length} سجل'),
          ],
        ),
        const SizedBox(height: 8),
        if (_debts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('لا توجد ديون مسجلة')),
          )
        else
          ..._debts.asMap().entries.map((entry) {
            final debt = entry.value;
            final isOwedToMe = debt.direction == DebtDirection.owedToMe;
            return Card(
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                leading: Icon(
                  isOwedToMe ? Icons.call_received : Icons.call_made,
                  color: isOwedToMe
                      ? const Color(0xff21866f)
                      : const Color(0xffd66b5f),
                ),
                title: Text(
                  debt.person,
                  style: TextStyle(
                    decoration: debt.isSettled
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                subtitle: Text(
                  debt.excessAmount > 0
                      ? 'تم السداد مع زيادة ${_formatAmount(debt.excessAmount)} ${debt.currency.symbol}'
                      : debt.isSettled
                      ? 'تمت التسوية'
                      : '${isOwedToMe ? 'لي عنده' : 'عليّ له'} · متبقي ${_formatAmount(debt.remainingAmount)} ${debt.currency.symbol}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_formatAmount(debt.amount)} ${debt.currency.symbol}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      tooltip: 'تسجيل دفعة',
                      onPressed: () => _recordPayment(entry.key),
                      icon: const Icon(Icons.payments_outlined),
                    ),
                    IconButton(
                      tooltip: 'حذف الدين',
                      onPressed: () => _confirmRemoveDebt(entry.key),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _DebtPaymentDialog extends StatefulWidget {
  const _DebtPaymentDialog({
    required this.debt,
    required this.formatAmount,
    required this.onSave,
  });

  final DebtRecord debt;
  final String Function(double) formatAmount;
  final ValueChanged<double> onSave;

  @override
  State<_DebtPaymentDialog> createState() => _DebtPaymentDialogState();
}

class _DebtPaymentDialogState extends State<_DebtPaymentDialog> {
  final _paymentController = TextEditingController();

  @override
  void dispose() {
    _paymentController.dispose();
    super.dispose();
  }

  void _save() {
    final payment = double.tryParse(
      _paymentController.text.trim().replaceAll(',', '.'),
    );
    if (payment == null || payment <= 0) return;
    widget.onSave(payment);
  }

  @override
  Widget build(BuildContext context) {
    final debt = widget.debt;
    return AlertDialog(
      title: const Text('تسجيل دفعة'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'المتبقي: ${widget.formatAmount(debt.remainingAmount)} ${debt.currency.symbol}',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _paymentController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'مبلغ الدفعة (${debt.currency.code})',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _save, child: const Text('حفظ الدفعة')),
      ],
    );
  }
}

class _DebtSummaryTile extends StatelessWidget {
  const _DebtSummaryTile({
    required this.label,
    required this.amount,
    required this.currency,
    required this.color,
    required this.formatAmount,
  });

  final String label;
  final double amount;
  final MoneyCurrency currency;
  final Color color;
  final String Function(double) formatAmount;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: color)),
            const SizedBox(height: 6),
            Text(
              '${formatAmount(amount)} ${currency.symbol}',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.income,
    required this.expenses,
    required this.currency,
    required this.formatAmount,
  });

  final double income;
  final double expenses;
  final MoneyCurrency currency;
  final String Function(double) formatAmount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xff176b5d),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ملخص اليوم (${currency.label})',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 10),
          Text(
            'الرصيد الصافي: ${formatAmount(income - expenses)} ${currency.symbol}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'دخل: ${formatAmount(income)} ${currency.symbol}',
                style: const TextStyle(color: Colors.white),
              ),
              Text(
                'مصروف: ${formatAmount(expenses)} ${currency.symbol}',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IncomeGoalCard extends StatelessWidget {
  const _IncomeGoalCard({
    required this.goal,
    required this.achieved,
    required this.formatAmount,
    required this.formatDate,
    required this.onSetGoal,
  });

  final IncomeGoal? goal;
  final double achieved;
  final String Function(double) formatAmount;
  final String Function(DateTime) formatDate;
  final VoidCallback onSetGoal;

  @override
  Widget build(BuildContext context) {
    if (goal == null) {
      return Card(
        elevation: 0,
        color: const Color(0xfffff4df),
        child: ListTile(
          leading: const Icon(Icons.flag_outlined, color: Color(0xffb46b00)),
          title: const Text('حدد هدف الدخل'),
          subtitle: const Text('اختر المبلغ والفترة التي تريد تحقيقها'),
          trailing: IconButton(
            onPressed: onSetGoal,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ),
      );
    }

    final progress = (achieved / goal!.amount).clamp(0.0, 1.0).toDouble();
    final remaining = goal!.amount - achieved;
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'هدف الدخل',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                IconButton(
                  onPressed: onSetGoal,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            Text('${formatDate(goal!.start)} إلى ${formatDate(goal!.end)}'),
            const SizedBox(height: 4),
            Text(
              'تم تحقيق ${formatAmount(achieved)} من ${formatAmount(goal!.amount)} ${goal!.currency.symbol}',
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xff176b5d),
              backgroundColor: const Color(0xffdfeae6),
            ),
            const SizedBox(height: 8),
            Text(
              remaining > 0
                  ? 'متبقي ${formatAmount(remaining)} ${goal!.currency.symbol} (${(progress * 100).toStringAsFixed(0)}%)'
                  : 'تم تحقيق الهدف أو تجاوزه',
              style: TextStyle(
                color: remaining > 0
                    ? Colors.grey.shade700
                    : const Color(0xff176b5d),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencySelector extends StatelessWidget {
  const _CurrencySelector({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final MoneyCurrency value;
  final ValueChanged<MoneyCurrency> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<MoneyCurrency>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.currency_exchange),
        border: const OutlineInputBorder(),
      ),
      items: MoneyCurrency.values
          .map(
            (currency) => DropdownMenuItem(
              value: currency,
              child: Text('${currency.label} (${currency.code})'),
            ),
          )
          .toList(),
      onChanged: (currency) {
        if (currency != null) onChanged(currency);
      },
    );
  }
}

class _SettingsCurrencySelector extends StatelessWidget {
  const _SettingsCurrencySelector({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final MoneyCurrency value;
  final ValueChanged<MoneyCurrency> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MoneyCurrency>(
          value: value,
          isExpanded: true,
          items: MoneyCurrency.values
              .map(
                (currency) => DropdownMenuItem(
                  value: currency,
                  child: Text('${currency.label} (${currency.code})'),
                ),
              )
              .toList(),
          onChanged: (currency) {
            if (currency != null) onChanged(currency);
          },
        ),
      ),
    );
  }
}

class _EntryForm extends StatelessWidget {
  const _EntryForm({
    required this.type,
    required this.currency,
    required this.titleController,
    required this.amountController,
    required this.onTypeChanged,
    required this.onCurrencyChanged,
    required this.onSubmit,
  });

  final EntryType type;
  final MoneyCurrency currency;
  final TextEditingController titleController;
  final TextEditingController amountController;
  final ValueChanged<EntryType> onTypeChanged;
  final ValueChanged<MoneyCurrency> onCurrencyChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'إضافة عملية',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SegmentedButton<EntryType>(
              segments: const [
                ButtonSegment(
                  value: EntryType.expense,
                  label: Text('مصروف'),
                  icon: Icon(Icons.arrow_upward),
                ),
                ButtonSegment(
                  value: EntryType.income,
                  label: Text('دخل'),
                  icon: Icon(Icons.arrow_downward),
                ),
              ],
              selected: {type},
              onSelectionChanged: (selection) => onTypeChanged(selection.first),
            ),
            const SizedBox(height: 12),
            _CurrencySelector(
              label: 'عملة العملية',
              value: currency,
              onChanged: onCurrencyChanged,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'الوصف',
                hintText: 'مثال: راتب، غداء، مواصلات',
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                labelText: 'المبلغ',
                suffixText: currency.symbol,
                prefixIcon: const Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onSubmit,
              icon: const Icon(Icons.add),
              label: const Text('إضافة العملية'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.amount,
    required this.currency,
    required this.date,
    required this.onDelete,
  });

  final MoneyEntry entry;
  final String amount;
  final MoneyCurrency currency;
  final String date;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isIncome = entry.type == EntryType.income;
    return Card(
      elevation: 0,
      color: Colors.white,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isIncome
              ? const Color(0xffe1f1ed)
              : const Color(0xffffe8e5),
          child: Icon(
            isIncome ? Icons.arrow_downward : Icons.arrow_upward,
            color: isIncome ? const Color(0xff176b5d) : Colors.red,
          ),
        ),
        title: Text(
          entry.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(date),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${isIncome ? '+' : '-'}$amount ${currency.symbol}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isIncome ? const Color(0xff176b5d) : Colors.red.shade700,
              ),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: 'حذف العملية',
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.calendar_today_outlined),
        label: Text(label),
      ),
    );
  }
}

class _EmptyEntries extends StatelessWidget {
  const _EmptyEntries();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 10),
          Text(
            'لا توجد عمليات مسجلة اليوم',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _TopEntry {
  const _TopEntry({required this.title, required this.amount});

  final String title;
  final double amount;
}

class _ChartBucket {
  _ChartBucket({required this.label});

  final String label;
  double income = 0;
  double expense = 0;
}

class _ReportSummary extends StatelessWidget {
  const _ReportSummary({
    required this.period,
    required this.income,
    required this.expenses,
    required this.currency,
    required this.formatAmount,
  });

  final String period;
  final double income;
  final double expenses;
  final MoneyCurrency currency;
  final String Function(double) formatAmount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xff173c36),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$period: صافي الرصيد',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            '${formatAmount(income - expenses)} ${currency.symbol}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SummaryValue(
                  label: 'الدخل',
                  amount: income,
                  currency: currency,
                  color: const Color(0xff83d5bc),
                  formatAmount: formatAmount,
                ),
              ),
              Expanded(
                child: _SummaryValue(
                  label: 'المصروفات',
                  amount: expenses,
                  currency: currency,
                  color: const Color(0xffffa49b),
                  formatAmount: formatAmount,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.label,
    required this.amount,
    required this.currency,
    required this.color,
    required this.formatAmount,
  });

  final String label;
  final double amount;
  final MoneyCurrency currency;
  final Color color;
  final String Function(double) formatAmount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: color)),
        const SizedBox(height: 3),
        Text(
          '${formatAmount(amount)} ${currency.symbol}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ReportChart extends StatelessWidget {
  const _ReportChart({
    required this.buckets,
    required this.currency,
    required this.formatAmount,
  });

  final List<_ChartBucket> buckets;
  final MoneyCurrency currency;
  final String Function(double) formatAmount;

  @override
  Widget build(BuildContext context) {
    var maximum = 0.0;
    for (final bucket in buckets) {
      if (bucket.income > maximum) maximum = bucket.income;
      if (bucket.expense > maximum) maximum = bucket.expense;
    }

    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'حركة الدخل والمصروفات',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _ChartLegend(color: const Color(0xff21866f), label: 'دخل'),
                const SizedBox(width: 18),
                _ChartLegend(color: const Color(0xffd66b5f), label: 'مصروف'),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 132,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: buckets
                    .map(
                      (bucket) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _ChartBar(
                                      value: bucket.income,
                                      maximum: maximum,
                                      color: const Color(0xff21866f),
                                    ),
                                    const SizedBox(width: 2),
                                    _ChartBar(
                                      value: bucket.expense,
                                      maximum: maximum,
                                      color: const Color(0xffd66b5f),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                bucket.label,
                                maxLines: 1,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            if (maximum > 0) ...[
              const SizedBox(height: 4),
              Text(
                'أعلى قيمة في الرسم: ${formatAmount(maximum)} ${currency.symbol}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChartBar extends StatelessWidget {
  const _ChartBar({
    required this.value,
    required this.maximum,
    required this.color,
  });

  final double value;
  final double maximum;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final height = maximum == 0
        ? 0.0
        : (value / maximum * 100).clamp(0.0, 100.0);
    return Container(
      width: 7,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 9, height: 9, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ),
      ],
    );
  }
}

class _TopEntriesSection extends StatelessWidget {
  const _TopEntriesSection({
    required this.title,
    required this.emptyText,
    required this.entries,
    required this.currency,
    required this.color,
    required this.icon,
    required this.formatAmount,
  });

  final String title;
  final String emptyText;
  final List<_TopEntry> entries;
  final MoneyCurrency currency;
  final Color color;
  final IconData icon;
  final String Function(double) formatAmount;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  emptyText,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            else
              ...entries.asMap().entries.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: CircleAvatar(
                    radius: 15,
                    backgroundColor: color.withValues(alpha: 0.1),
                    child: Text(
                      '${item.key + 1}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(item.value.title),
                  trailing: Text(
                    '${formatAmount(item.value.amount)} ${currency.symbol}',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyConverter extends StatefulWidget {
  const _CurrencyConverter();

  @override
  State<_CurrencyConverter> createState() => _CurrencyConverterState();
}

class _CurrencyConverterState extends State<_CurrencyConverter> {
  final _amountController = TextEditingController();
  final _rateController = TextEditingController(text: '1310');
  bool _dollarToDinar = true;

  double? get _convertedAmount {
    final amount = double.tryParse(
      _amountController.text.trim().replaceAll(',', '.'),
    );
    final rate = double.tryParse(
      _rateController.text.trim().replaceAll(',', '.'),
    );
    if (amount == null || rate == null || amount < 0 || rate <= 0) return null;
    return _dollarToDinar ? amount * rate : amount / rate;
  }

  String _format(double value) => value.toStringAsFixed(value % 1 == 0 ? 0 : 2);

  @override
  void dispose() {
    _amountController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inputCurrency = _dollarToDinar ? 'دولار أمريكي' : 'دينار عراقي';
    final outputCurrency = _dollarToDinar ? 'دينار عراقي' : 'دولار أمريكي';
    final inputCode = _dollarToDinar ? 'USD' : 'IQD';
    final outputCode = _dollarToDinar ? 'IQD' : 'USD';
    final result = _convertedAmount;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Text(
          'تحويل بين الدولار والدينار',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: const Color(0xff173c36),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'أدخل المبلغ وسعر الصرف لحساب القيمة المقابلة',
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        Card(
          elevation: 0,
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _amountController,
                  autofocus: false,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'المبلغ ($inputCurrency)',
                    suffixText: inputCode,
                    prefixIcon: const Icon(Icons.payments_outlined),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: IconButton.filledTonal(
                    tooltip: 'تبديل اتجاه التحويل',
                    onPressed: () =>
                        setState(() => _dollarToDinar = !_dollarToDinar),
                    icon: const Icon(Icons.swap_vert),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _rateController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'سعر صرف 1 دولار بالدينار',
                    suffixText: 'د.ع',
                    prefixIcon: Icon(Icons.currency_exchange),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xff176b5d),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'الناتج بـ $outputCurrency',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Text(
                result == null ? '--' : _format(result),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(outputCode, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'السعر الافتراضي إرشادي فقط، ويمكن تعديله حسب سعر الصرف الذي تعتمد عليه.',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () {
            _amountController.clear();
            setState(() {});
          },
          icon: const Icon(Icons.clear),
          label: const Text('مسح المبلغ'),
        ),
      ],
    );
  }
}
