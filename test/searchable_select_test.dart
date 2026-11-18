import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerline/presentation/widgets/searchable_select.dart';

void main() {
  testWidgets('search popup is bounded and scrolls internally', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final options = [
      for (var i = 0; i < 40; i++)
        SearchableSelectOption(value: i, label: 'Currency option $i'),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 260,
            child: SearchableSelect<int>(
              id: 'currency',
              label: 'Currency',
              searchHint: 'Search currencies',
              emptyLabel: 'No currencies found',
              options: options,
              value: 0,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    ));

    await tester.tap(
      find.byKey(const ValueKey('searchable-select-trigger-currency')),
    );
    await tester.pumpAndSettle();

    final popup = find.byKey(const ValueKey('searchable-select-popup-currency'));
    expect(popup, findsOneWidget);
    final popupRect = tester.getRect(popup);
    expect(popupRect.height, lessThanOrEqualTo(320));
    expect(popupRect.left, greaterThanOrEqualTo(0));
    expect(popupRect.right, lessThanOrEqualTo(800));
    expect(popupRect.width, lessThanOrEqualTo(480));
    expect(find.text('Currency option 0'), findsWidgets);

    await tester.drag(
      find.byKey(const ValueKey('searchable-select-list-currency')),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    expect(find.text('Currency option 5'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('searchable-select-search-currency')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('searchable-select-search-currency')),
      'Currency option 39',
    );
    await tester.pumpAndSettle();
    expect(find.text('Currency option 39'), findsNWidgets(2));
    expect(popupRect.height, lessThanOrEqualTo(320));
  });

  testWidgets('autoOpen displays the popup on first render', (tester) async {
    tester.view.physicalSize = const Size(640, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: SearchableSelect<String>(
            id: 'auto-open',
            label: 'Currency',
            searchHint: 'Search currencies',
            emptyLabel: 'No currencies',
            options: const [
              SearchableSelectOption(value: 'USD', label: 'USD · US Dollar'),
              SearchableSelectOption(value: 'EUR', label: 'EUR · Euro'),
            ],
            value: 'USD',
            onChanged: (_) {},
            autoOpen: true,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('searchable-select-popup-auto-open')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard selection commits the highlighted option', (tester) async {
    tester.view.physicalSize = const Size(700, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: SearchableSelect<String>(
            id: 'language',
            label: 'Language',
            searchHint: 'Search',
            emptyLabel: 'No options',
            options: const [
              SearchableSelectOption(value: 'en', label: 'English'),
              SearchableSelectOption(value: 'fa', label: 'Persian'),
              SearchableSelectOption(value: 'de', label: 'German'),
            ],
            value: 'en',
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    ));

    await tester.tap(
      find.byKey(const ValueKey('searchable-select-trigger-language')),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selected, 'fa');
    expect(
      find.byKey(const ValueKey('searchable-select-popup-language')),
      findsNothing,
    );
  });

  testWidgets('popup remains inside a narrow RTL viewport', (tester) async {
    tester.view.physicalSize = const Size(480, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: 300,
              child: SearchableSelect<String>(
                id: 'rtl',
                label: 'زبان',
                searchHint: 'جستجو',
                emptyLabel: 'نتیجه‌ای نیست',
                options: const [
                  SearchableSelectOption(value: 'fa', label: 'فارسی'),
                  SearchableSelectOption(value: 'en', label: 'English'),
                ],
                value: 'fa',
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('searchable-select-trigger-rtl')));
    await tester.pumpAndSettle();
    final popup = tester.getRect(
      find.byKey(const ValueKey('searchable-select-popup-rtl')),
    );
    expect(popup.left, greaterThanOrEqualTo(0));
    expect(popup.right, lessThanOrEqualTo(480));
    expect(find.text('فارسی'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
