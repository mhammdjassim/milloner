// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milloner/app_database.dart';
import 'package:milloner/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    AppDatabase.useInMemoryDatabaseForTesting = true;
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    await AppDatabase.resetForTesting();
  });

  testWidgets('records a debt and updates the owed-to-me summary', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.text('الديون'));
    await tester.pumpAndSettle();
    await _waitForDatabase(tester, AppDatabase.loadDebts);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('جار تحميل البيانات...'), findsNothing);
    expect(find.text('تعذر تحميل البيانات المحفوظة'), findsNothing);

    expect(find.text('تسجيل دين'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'أحمد');
    await tester.enterText(find.byType(TextField).last, '25000');
    await tester.ensureVisible(find.text('حفظ الدين'));
    await tester.tap(find.text('حفظ الدين'));
    await tester.pumpAndSettle();

    expect(find.text('أحمد'), findsOneWidget);
    expect(find.text('لي عنده · متبقي 25000 د.ع'), findsOneWidget);
    expect(find.text('25000 د.ع'), findsNWidgets(2));
    expect(find.textContaining('متبقي 25000 د.ع'), findsOneWidget);

    await tester.tap(find.byTooltip('تسجيل دفعة'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '10000');
    await tester.tap(find.text('حفظ الدفعة'));
    await tester.pumpAndSettle();
    expect(find.textContaining('متبقي 15000 د.ع'), findsOneWidget);

    await tester.tap(find.byTooltip('تسجيل دفعة'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '20000');
    await tester.tap(find.text('حفظ الدفعة'));
    await tester.pumpAndSettle();
    expect(find.text('تم السداد مع زيادة 5000 د.ع'), findsOneWidget);

    await tester.tap(find.byTooltip('حذف الدين'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد حذف الدين'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('أحمد'), findsOneWidget);

    await tester.tap(find.byTooltip('حذف الدين'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف'));
    await tester.pumpAndSettle();
    expect(find.text('أحمد'), findsNothing);
  });

  testWidgets('adds an expense with its date and amount', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpApp(tester);

    final textFields = find.byType(TextField);
    await tester.enterText(textFields.first, 'غداء');
    await tester.enterText(textFields.last, '5000');
    final addButton = find.widgetWithText(FilledButton, 'إضافة العملية');
    await tester.ensureVisible(addButton);
    await tester.pumpAndSettle();
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(find.text('غداء'), findsOneWidget);
    expect(find.text('-5000 د.ع'), findsOneWidget);

    await tester.tap(find.byTooltip('حذف العملية'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد حذف العملية'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('غداء'), findsOneWidget);

    await tester.tap(find.byTooltip('حذف العملية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف'));
    await tester.pumpAndSettle();
    expect(find.text('غداء'), findsNothing);
  });

  testWidgets('adds income and sets an income goal', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('تحديد هدف الدخل'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '50000');
    await tester.tap(find.text('حفظ الهدف'));
    await tester.pumpAndSettle();

    expect(find.textContaining('تم تحقيق 0 من 50000 د.ع'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('دخل'));
    final textFields = find.byType(TextField);
    await tester.enterText(textFields.first, 'عمل حر');
    await tester.enterText(textFields.last, '50000');
    final addButton = find.widgetWithText(FilledButton, 'إضافة العملية');
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(addButton);
    await tester.pump();

    expect(find.text('+50000 د.ع'), findsOneWidget);
  });

  testWidgets('records an expense in the selected dollar currency', (
    tester,
  ) async {
    await _pumpApp(tester);

    final currencySelectors = find.byType(
      DropdownButtonFormField<MoneyCurrency>,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(currencySelectors.last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('الدولار الأمريكي (USD)').last);
    await tester.pumpAndSettle();

    final textFields = find.byType(TextField);
    await tester.enterText(textFields.first, 'قهوة');
    await tester.enterText(textFields.last, '2');
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'إضافة العملية'));
    await tester.pump();

    expect(find.text('-2 \$'), findsOneWidget);
  });

  testWidgets('top menu provides settings, about, and backup', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('القائمة'));
    await tester.pumpAndSettle();
    expect(find.text('الإعدادات'), findsOneWidget);
    expect(find.text('حول التطبيق'), findsOneWidget);
    expect(find.text('نسخ احتياطي للبيانات'), findsOneWidget);

    await tester.tap(find.text('الإعدادات'));
    await tester.pumpAndSettle();
    expect(find.text('العملة الافتراضية للعملية'), findsOneWidget);
    final currencyDropdowns = find.byType(DropdownButton<MoneyCurrency>);
    await tester.tap(currencyDropdowns.last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('الدولار الأمريكي (USD)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    final savedSettings = await _waitForDatabase(
      tester,
      AppDatabase.loadSettings,
    );
    expect(savedSettings?['entry_currency'], MoneyCurrency.usd.name);

    await tester.tap(find.byTooltip('القائمة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حول التطبيق'));
    await tester.pumpAndSettle();
    expect(find.text('مصروفي اليومي'), findsWidgets);
    expect(find.textContaining('لتسجيل الدخل والمصروفات'), findsOneWidget);
  });
}

Future<void> _pumpApp(WidgetTester tester) async {
  await _waitForDatabase(tester, () async {
    await AppDatabase.loadSettings();
    await AppDatabase.loadEntries();
    await AppDatabase.loadDebts();
  });
  await tester.pumpWidget(const DailyExpensesApp());
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
  expect(find.text('جار تحميل البيانات...'), findsNothing);
}

Future<T?> _waitForDatabase<T>(WidgetTester tester, Future<T> Function() load) {
  return tester.runAsync(() async {
    final result = await load();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return result;
  });
}
