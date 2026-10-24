import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:milloner/app_database.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    AppDatabase.useInMemoryDatabaseForTesting = true;
    AppDatabase.migrateLegacyPreferencesForTesting = true;
    SharedPreferences.setMockInitialValues({
      'money_entries': jsonEncode([
        {
          'title': 'راتب',
          'amount': 100000,
          'type': 'income',
          'currency': 'iqd',
          'dateTime': '2026-10-23T09:00:00.000',
        },
      ]),
      'debt_records': jsonEncode([
        {
          'person': 'أحمد',
          'amount': 25000,
          'currency': 'iqd',
          'direction': 'owedToMe',
          'dateTime': '2026-10-22T09:00:00.000',
          'paidAmount': 5000,
        },
      ]),
      'income_goal': jsonEncode({
        'amount': 200000,
        'currency': 'iqd',
        'start': '2026-10-01T00:00:00.000',
        'end': '2026-10-31T00:00:00.000',
      }),
      'display_currency': 'usd',
      'entry_currency': 'iqd',
    });
  });

  tearDown(() async {
    await AppDatabase.resetForTesting();
    AppDatabase.migrateLegacyPreferencesForTesting = false;
    AppDatabase.databasePathForTesting = null;
  });

  test('migrates existing records and settings to SQLite', () async {
    final entries = await AppDatabase.loadEntries();
    final debts = await AppDatabase.loadDebts();
    final settings = await AppDatabase.loadSettings();

    expect(entries, hasLength(1));
    expect(entries.single['title'], 'راتب');
    expect(entries.single['amount'], 100000);
    expect(debts, hasLength(1));
    expect(debts.single['person'], 'أحمد');
    expect(debts.single['paidAmount'], 5000);
    expect(settings['display_currency'], 'usd');
    expect(settings['entry_currency'], 'iqd');
    expect(jsonDecode(settings['income_goal']!)['amount'], 200000);
  });

  test('saved records remain after closing and reopening SQLite', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'what_lose_sqlite_test_',
    );
    AppDatabase.databasePathForTesting = path.join(
      temporaryDirectory.path,
      'app.db',
    );
    SharedPreferences.setMockInitialValues({});

    try {
      await AppDatabase.saveAppData(
        entries: [
          {
            'title': 'غداء',
            'amount': 5000.0,
            'type': 'expense',
            'currency': 'iqd',
            'dateTime': '2026-10-23T13:00:00.000',
          },
        ],
        settings: {'display_currency': 'usd'},
      );
      await AppDatabase.saveDebts([
        {
          'person': 'سارة',
          'amount': 10000.0,
          'currency': 'iqd',
          'direction': 'iOwe',
          'dateTime': '2026-10-23T13:00:00.000',
          'paidAmount': 0.0,
        },
      ]);
      await AppDatabase.resetForTesting();

      expect((await AppDatabase.loadEntries()).single['title'], 'غداء');
      expect((await AppDatabase.loadDebts()).single['person'], 'سارة');
      expect((await AppDatabase.loadSettings())['display_currency'], 'usd');

      final backup = jsonDecode(await AppDatabase.exportBackupJson());
      expect(backup['format'], 'what_lose_backup');
      expect(backup['version'], 1);
      expect(backup['entries'], hasLength(1));
      expect(backup['debts'], hasLength(1));
      expect(backup['settings']['display_currency'], 'usd');
    } finally {
      await AppDatabase.resetForTesting();
      await temporaryDirectory.delete(recursive: true);
      AppDatabase.databasePathForTesting = null;
    }
  });
}
