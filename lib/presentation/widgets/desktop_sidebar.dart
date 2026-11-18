import 'package:material_ui/material_ui.dart';

import '../app_strings.dart';

typedef LedgerNavDestination = (String, IconData, IconData);

class LedgerDesktopSidebar extends StatefulWidget {
  const LedgerDesktopSidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.collapsed,
    this.canToggleExpanded = true,
    required this.onDestinationSelected,
    required this.onCollapsedChanged,
  });

  final List<LedgerNavDestination> destinations;
  final int selectedIndex;
  final bool collapsed;
  final bool canToggleExpanded;
  final ValueChanged<int> onDestinationSelected;
  final ValueChanged<bool> onCollapsedChanged;

  @override
  State<LedgerDesktopSidebar> createState() => _LedgerDesktopSidebarState();
}

class _LedgerDesktopSidebarState extends State<LedgerDesktopSidebar> {
  final TextEditingController _searchController = TextEditingController();

  static const _sections = <({String labelKey, List<int> indices})>[
    (labelKey: 'navWorkspace', indices: [0]),
    (labelKey: 'navAccounting', indices: [1, 2, 5]),
    (labelKey: 'navSales', indices: [4]),
    (labelKey: 'navInventory', indices: [3]),
    (labelKey: 'navTools', indices: [6, 8]),
    (labelKey: 'navAdministration', indices: [7]),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final expanded = !widget.collapsed;
    return AnimatedContainer(
      key: const Key('ledgerline-desktop-sidebar'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: expanded ? 252 : 76,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          right: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(expanded ? 14 : 0, 10, expanded ? 12 : 0, 8),
            child: Row(
              mainAxisAlignment: expanded ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
              children: [
                if (expanded) ...[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2EE),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.account_balance_wallet_rounded,
                        color: Color(0xFF087E78), size: 19),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr(context, 'appName'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
                if (widget.canToggleExpanded)
                  Tooltip(
                  message: tr(context, expanded ? 'collapseNavigation' : 'expandNavigation'),
                  child: IconButton(
                    key: const Key('desktop-sidebar-toggle'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => widget.onCollapsedChanged(expanded),
                    icon: Icon(
                      expanded ? Icons.keyboard_double_arrow_left_rounded : Icons.keyboard_double_arrow_right_rounded,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 12),
              child: TextField(
                key: const Key('desktop-sidebar-search-field'),
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: tr(context, 'searchNavigation'),
                  prefixIcon: const Icon(Icons.search_rounded, size: 19),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: tr(context, 'clearSearch'),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                ),
              ),
            )
          else
            Tooltip(
              message: tr(context, 'searchNavigation'),
              child: IconButton(
                key: const Key('desktop-sidebar-search-button'),
                onPressed: _showSearchDialog,
                icon: const Icon(Icons.search_rounded),
              ),
            ),
          Expanded(
            child: _navigationList(
              context,
              collapsed: !expanded,
              query: _searchController.text.trim().toLowerCase(),
            ),
          ),

        ],
      ),
    );
  }

  Widget _navigationList(
    BuildContext context, {
    required bool collapsed,
    required String query,
  }) {
    final colors = Theme.of(context).colorScheme;
    final children = <Widget>[];
    for (final section in _sections) {
      final entries = section.indices
          .where((index) => index < widget.destinations.length)
          .where((index) {
            final label = tr(context, widget.destinations[index].$1).toLowerCase();
            return query.isEmpty || label.contains(query);
          })
          .toList(growable: false);
      if (entries.isEmpty) continue;
      if (!collapsed) {
        children.add(
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(18, 14, 14, 6),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                tr(context, section.labelKey),
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.45,
                ),
              ),
            ),
          ),
        );
      }
      for (final index in entries) {
        children.add(_destinationTile(context, index, collapsed: collapsed));
      }
    }
    if (children.isEmpty) {
      return Center(child: Text(tr(context, 'noNavigationResults')));
    }
    return ListView(
      key: const Key('desktop-sidebar-items'),
      padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 10, 12),
      children: children,
    );
  }

  Widget _destinationTile(
    BuildContext context,
    int index, {
    required bool collapsed,
  }) {
    final destination = widget.destinations[index];
    final selected = widget.selectedIndex == index;
    final colors = Theme.of(context).colorScheme;
    final label = tr(context, destination.$1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: collapsed ? label : '',
        preferBelow: false,
        child: Material(
          color: selected ? colors.primaryContainer.withValues(alpha: 0.72) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: Key('desktop-sidebar-destination-$index'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => widget.onDestinationSelected(index),
            child: SizedBox(
              height: 46,
              child: Row(
                mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  SizedBox(
                    width: collapsed ? 48 : 46,
                    child: Icon(
                      selected ? destination.$2 : destination.$3,
                      size: 20,
                      color: selected ? colors.primary : colors.onSurfaceVariant,
                    ),
                  ),
                  if (!collapsed)
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? colors.primary : colors.onSurface,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSearchDialog() async {
    final controller = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final query = controller.text.trim().toLowerCase();
            final matches = widget.destinations.asMap().entries.where((entry) {
              return tr(context, entry.value.$1).toLowerCase().contains(query);
            }).toList(growable: false);
            return Dialog(
              child: SizedBox(
                width: 420,
                height: 420,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        tr(context, 'searchNavigation'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          hintText: tr(context, 'searchNavigation'),
                          prefixIcon: const Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: matches.isEmpty
                            ? Center(child: Text(tr(context, 'noNavigationResults')))
                            : ListView.builder(
                                itemCount: matches.length,
                                itemBuilder: (context, index) {
                                  final entry = matches[index];
                                  return ListTile(
                                    key: Key('desktop-navigation-search-result-${entry.key}'),
                                    leading: Icon(entry.value.$3),
                                    title: Text(tr(context, entry.value.$1)),
                                    onTap: () {
                                      widget.onDestinationSelected(entry.key);
                                      Navigator.pop(dialogContext);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            );
          },
        ),
      );
    } finally {
      controller.dispose();
    }
  }
}
