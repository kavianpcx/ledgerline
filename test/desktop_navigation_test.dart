import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ledgerline/presentation/navigation_presentation.dart';
import 'package:ledgerline/presentation/more_tools_page.dart';
import 'package:ledgerline/presentation/widgets/desktop_sidebar.dart';

const _destinations = <LedgerNavDestination>[
  ('overview', Icons.grid_view_rounded, Icons.grid_view_outlined),
  ('entries', Icons.receipt_long_rounded, Icons.receipt_long_outlined),
  ('accounts', Icons.account_tree_rounded, Icons.account_tree_outlined),
  ('products', Icons.inventory_2_rounded, Icons.inventory_2_outlined),
  ('invoices', Icons.request_quote_rounded, Icons.request_quote_outlined),
  ('reports', Icons.analytics_rounded, Icons.analytics_outlined),
  ('smartImport', Icons.file_upload_outlined, Icons.file_upload_outlined),
  ('settings', Icons.settings_rounded, Icons.settings_outlined),
  ('pointOfSale', Icons.shopping_cart_rounded, Icons.shopping_cart_outlined),
  ('more', Icons.more_horiz_rounded, Icons.more_horiz_outlined),
];

void main() {
  test('Windows always uses a left sidebar regardless of window width', () {
    for (final width in [1440.0, 980.0, 560.0, 360.0]) {
      expect(
        navigationPresentationFor(windowsDesktop: true, availableWidth: width),
        LedgerNavigationPresentation.windowsSidebar,
        reason: 'Windows width $width must not switch to bottom navigation',
      );
    }
  });

  test('non-Windows layouts remain adaptive for tablets and phones', () {
    expect(
      navigationPresentationFor(windowsDesktop: false, availableWidth: 1024),
      LedgerNavigationPresentation.tabletRail,
    );
    expect(
      navigationPresentationFor(windowsDesktop: false, availableWidth: 600),
      LedgerNavigationPresentation.mobileBottomBar,
    );
  });

  test('Windows sidebar expands only when there is room or the user requests it', () {
    expect(
      desktopSidebarExpandedFor(availableWidth: 1440, collapsedPreference: false),
      isTrue,
    );
    expect(
      desktopSidebarExpandedFor(availableWidth: 900, collapsedPreference: false),
      isFalse,
    );
    expect(
      desktopSidebarExpandedFor(availableWidth: 900, collapsedPreference: false, expandedAtMediumWidth: true),
      isTrue,
    );
    expect(
      desktopSidebarExpandedFor(availableWidth: 560, collapsedPreference: false, expandedAtMediumWidth: true),
      isFalse,
    );
    expect(
      desktopSidebarExpandedFor(availableWidth: 1440, collapsedPreference: true),
      isFalse,
    );
  });

  testWidgets('expanded sidebar groups, searches, and selects destinations', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            LedgerDesktopSidebar(
              destinations: _destinations,
              selectedIndex: 0,
              collapsed: false,
              onDestinationSelected: selected.add,
              onCollapsedChanged: (_) {},
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    ));

    expect(find.byKey(const Key('ledgerline-desktop-sidebar')), findsOneWidget);
    expect(find.text('Accounting'), findsOneWidget);
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Point of Sale'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('desktop-sidebar-search-field')), 'Products');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('desktop-sidebar-destination-3')), findsOneWidget);
    expect(find.byKey(const Key('desktop-sidebar-destination-1')), findsNothing);
    await tester.tap(find.byKey(const Key('desktop-sidebar-destination-3')));
    expect(selected, [3]);
  });

  testWidgets('point of sale appears in the Sales group and stays searchable', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            LedgerDesktopSidebar(
              destinations: _destinations,
              selectedIndex: 0,
              collapsed: false,
              onDestinationSelected: selected.add,
              onCollapsedChanged: (_) {},
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    ));

    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Point of Sale'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('desktop-sidebar-search-field')), 'point of sale');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('desktop-sidebar-destination-8')), findsOneWidget);
    await tester.tap(find.byKey(const Key('desktop-sidebar-destination-8')));
    expect(selected, [8]);
  });

  testWidgets('very narrow sidebar keeps navigation without a nonfunctional expand control', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            LedgerDesktopSidebar(
              destinations: _destinations,
              selectedIndex: 0,
              collapsed: true,
              canToggleExpanded: false,
              onDestinationSelected: (_) {},
              onCollapsedChanged: (_) {},
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    ));

    expect(find.byKey(const Key('desktop-sidebar-toggle')), findsNothing);
    expect(find.byTooltip('Products'), findsOneWidget);
    expect(find.byKey(const Key('desktop-sidebar-search-button')), findsOneWidget);
  });

  testWidgets('collapsed sidebar exposes tooltips and searchable page selection', (tester) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selected = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            LedgerDesktopSidebar(
              destinations: _destinations,
              selectedIndex: 0,
              collapsed: true,
              onDestinationSelected: selected.add,
              onCollapsedChanged: (_) {},
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    ));

    expect(find.byTooltip('Products'), findsOneWidget);
    await tester.tap(find.byKey(const Key('desktop-sidebar-search-button')));
    await tester.pumpAndSettle();
    final dialogSize = tester.getSize(
      find.byKey(const Key('desktop-navigation-search-dialog')),
    );
    expect(dialogSize.width, lessThanOrEqualTo(280));
    expect(dialogSize.height, lessThanOrEqualTo(420));
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField).last, 'Products');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('desktop-navigation-search-result-3')), findsOneWidget);
    await tester.tap(find.byKey(const Key('desktop-navigation-search-result-3')));
    await tester.pumpAndSettle();
    expect(selected, [3]);
  });

  testWidgets('More tools lists utilities instead of repeating accounting pages', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MoreToolsPage(
          marketDisplayCurrency: 'TOMAN',
          onMarketDisplayCurrencyChanged: (_) async {},
          onOpenSmartImport: () {},
        ),
      ),
    ));

    expect(find.byKey(const Key('more-tool-calculator')), findsOneWidget);
    expect(find.byKey(const Key('more-tool-currency')), findsOneWidget);
    expect(find.byKey(const Key('more-tool-smart-import')), findsOneWidget);
    expect(find.text('Accounts'), findsNothing);
    expect(find.text('Products'), findsNothing);
    expect(find.text('Reports'), findsNothing);
  });
}
