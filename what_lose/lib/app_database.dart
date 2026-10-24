import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_database_platform.dart' as platform;

class AppDatabase {
  AppDatabase._();

  static Database? _database;
  static Future<Database>? _openingDatabase;
  static bool _ffiFactoryInitialized = false;
  @visibleForTesting
  static bool useInMemoryDatabaseForTesting = false;
  @visibleForTesting
  static bool migrateLegacyPreferencesForTesting = false;
  @visibleForTesting
  static String? databasePathForTesting;

  @visibleForTesting
  static Future<void> resetForTesting() async {
    final database = _database;
    _database = null;
    _openingDatabase = null;
    await database?.close();
  }

  static Future<Database> get database {
    final database = _database;
    if (database != null) return Future.value(database);
    return _openingDatabase ??= _openDatabase().catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _openingDatabase = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  static Future<Database> _openDatabase() async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite storage is not configured for web.');
    }

    if (platform.isWindows || platform.isLinux) {
      sqfliteFfiInit();
      if (!_ffiFactoryInitialized) {
        databaseFactory = useInMemoryDatabaseForTesting
            ? databaseFactoryFfiNoIsolate
            : databaseFactoryFfi;
        _ffiFactoryInitialized = true;
      }
    }

    late final String databasePath;
    if (databasePathForTesting != null) {
      databasePath = databasePathForTesting!;
    } else if (useInMemoryDatabaseForTesting) {
      databasePath = inMemoryDatabasePath;
    } else if (platform.isWindows) {
      final appData = platform.environment('LOCALAPPDATA');
      if (appData == null || appData.isEmpty) {
        throw StateError('Windows application data directory is unavailable.');
      }
      databasePath = path.join(appData, 'what_lose', 'daily_expenses.db');
    } else if (platform.isLinux) {
      final dataHome = platform.environment('XDG_DATA_HOME');
      final home = platform.environment('HOME');
      final appData = dataHome != null && dataHome.isNotEmpty
          ? dataHome
          : home == null || home.isEmpty
          ? null
          : path.join(home, '.local', 'share');
      if (appData == null) {
        throw StateError('Linux application data directory is unavailable.');
      }
      databasePath = path.join(appData, 'what_lose', 'daily_expenses.db');
    } else if (platform.isMacOS) {
      final home = platform.environment('HOME');
      if (home == null || home.isEmpty) {
        throw StateError('macOS application data directory is unavailable.');
      }
      databasePath = path.join(
        home,
        'Library',
        'Application Support',
        'what_lose',
        'daily_expenses.db',
      );
    } else {
      databasePath = path.join(await getDatabasesPath(), 'daily_expenses.db');
    }
    final database = await openDatabase(
      databasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            amount REAL NOT NULL,
            type TEXT NOT NULL,
            currency TEXT NOT NULL,
            dateTime TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE debts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            person TEXT NOT NULL,
            amount REAL NOT NULL,
            currency TEXT NOT NULL,
            direction TEXT NOT NULL,
            dateTime TEXT NOT NULL,
            paidAmount REAL NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
    if (!useInMemoryDatabaseForTesting || migrateLegacyPreferencesForTesting) {
      try {
        await _migrateLegacyPreferences(database);
      } catch (_) {
        await database.close();
        rethrow;
      }
    }
    _database = database;
    return database;
  }

  static Future<void> _migrateLegacyPreferences(Database database) async {
    const migrationKey = 'legacy_preferences_migrated';
    final migration = await database.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [migrationKey],
      limit: 1,
    );
    if (migration.isNotEmpty) return;

    final preferences = await SharedPreferences.getInstance();
    final savedEntries = preferences.getString('money_entries');
    final savedDebts = preferences.getString('debt_records');

    await database.transaction((transaction) async {
      if (savedEntries != null) {
        final entries = jsonDecode(savedEntries) as List<dynamic>;
        for (final rawEntry in entries) {
          final entry = Map<String, dynamic>.from(rawEntry as Map);
          await transaction.insert('entries', {
            'title': entry['title'] as String,
            'amount': (entry['amount'] as num).toDouble(),
            'type': entry['type'] as String,
            'currency': entry['currency'] as String? ?? 'iqd',
            'dateTime': entry['dateTime'] as String,
          });
        }
      }

      if (savedDebts != null) {
        final debts = jsonDecode(savedDebts) as List<dynamic>;
        for (final rawDebt in debts) {
          final debt = Map<String, dynamic>.from(rawDebt as Map);
          await transaction.insert('debts', {
            'person': debt['person'] as String,
            'amount': (debt['amount'] as num).toDouble(),
            'currency': debt['currency'] as String? ?? 'iqd',
            'direction': debt['direction'] as String? ?? 'owedToMe',
            'dateTime': debt['dateTime'] as String,
            'paidAmount':
                (debt['paidAmount'] as num?)?.toDouble() ??
                ((debt['isSettled'] as bool? ?? false)
                    ? (debt['amount'] as num).toDouble()
                    : 0),
          });
        }
      }

      for (final key in ['income_goal', 'display_currency', 'entry_currency']) {
        final value = preferences.getString(key);
        if (value != null) {
          await transaction.insert('settings', {'key': key, 'value': value});
        }
      }

      await transaction.insert('settings', {
        'key': migrationKey,
        'value': 'true',
      });
    });
  }

  static Future<List<Map<String, Object?>>> loadEntries() async {
    if (kIsWeb) {
      final saved = (await SharedPreferences.getInstance()).getString(
        'money_entries',
      );
      if (saved == null) return [];
      return (jsonDecode(saved) as List<dynamic>)
          .map((entry) => Map<String, Object?>.from(entry as Map))
          .toList();
    }
    final db = await database;
    return db.query('entries', orderBy: 'id ASC');
  }

  static Future<void> saveAppData({
    required List<Map<String, Object?>> entries,
    required Map<String, String?> settings,
  }) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('money_entries', jsonEncode(entries));
      await preferences.setString(
        'display_currency',
        settings['display_currency'] ?? 'iqd',
      );
      await preferences.setString(
        'entry_currency',
        settings['entry_currency'] ?? 'iqd',
      );
      final incomeGoal = settings['income_goal'];
      if (incomeGoal == null) {
        await preferences.remove('income_goal');
      } else {
        await preferences.setString('income_goal', incomeGoal);
      }
      return;
    }
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete('entries');
      for (final entry in entries) {
        await transaction.insert('entries', entry);
      }
      for (final entry in settings.entries) {
        final value = entry.value;
        if (value == null) {
          await transaction.delete(
            'settings',
            where: 'key = ?',
            whereArgs: [entry.key],
          );
        } else {
          await transaction.insert('settings', {
            'key': entry.key,
            'value': value,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  static Future<List<Map<String, Object?>>> loadDebts() async {
    if (kIsWeb) {
      final saved = (await SharedPreferences.getInstance()).getString(
        'debt_records',
      );
      if (saved == null) return [];
      return (jsonDecode(saved) as List<dynamic>)
          .map((debt) => Map<String, Object?>.from(debt as Map))
          .toList();
    }
    final db = await database;
    return db.query('debts', orderBy: 'id ASC');
  }

  static Future<void> saveDebts(List<Map<String, Object?>> debts) async {
    if (kIsWeb) {
      await (await SharedPreferences.getInstance()).setString(
        'debt_records',
        jsonEncode(debts),
      );
      return;
    }
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete('debts');
      for (final debt in debts) {
        await transaction.insert('debts', debt);
      }
    });
  }

  static Future<Map<String, String>> loadSettings() async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final settings = <String, String>{};
      for (final key in ['income_goal', 'display_currency', 'entry_currency']) {
        final value = preferences.getString(key);
        if (value != null) settings[key] = value;
      }
      return settings;
    }
    final db = await database;
    final rows = await db.query('settings');
    return {
      for (final row in rows)
        if (row['key'] != 'legacy_preferences_migrated')
          row['key']! as String: row['value']! as String,
    };
  }

  static Future<String> exportBackupJson() async {
    final entries = await loadEntries();
    final debts = await loadDebts();
    final settings = await loadSettings();
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'what_lose_backup',
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'entries': entries,
      'debts': debts,
      'settings': settings,
    });
  }
}
