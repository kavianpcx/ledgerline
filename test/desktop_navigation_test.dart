import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ledgerline/presentation/navigation_presentation.dart';
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

    await tester.enterText(find.byKey(const Key('desktop-sidebar-search-field')), 'Products');
    await tester.pumpAndSettle();
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Entries'), findsNothing);
    await tester.tap(find.text('Products'));
    expect(selected, [3]);
  });

  testWidgets('collapsed sidebar exposes tooltips and searchable page selection', (tester) async {
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
    await tester.enterText(find.byType(TextField).last, 'Products');
    await tester.pumpAndSettle();
    expect(find.text('Products'), findsOneWidget);
    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();
    expect(selected, [3]);
  });
}
