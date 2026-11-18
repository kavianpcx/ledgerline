import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

class SearchableSelectOption<T> {
  const SearchableSelectOption({
    required this.value,
    required this.label,
    this.searchText,
  });

  final T value;
  final String label;
  final String? searchText;
}

class SearchableSelect<T> extends StatefulWidget {
  const SearchableSelect({
    super.key,
    required this.id,
    required this.label,
    required this.searchHint,
    required this.emptyLabel,
    required this.options,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.maxPopupHeight = 304,
    this.autoOpen = false,
  });

  final String id;
  final String label;
  final String searchHint;
  final String emptyLabel;
  final List<SearchableSelectOption<T>> options;
  final T? value;
  final ValueChanged<T?> onChanged;
  final bool enabled;
  final double maxPopupHeight;
  final bool autoOpen;

  @override
  State<SearchableSelect<T>> createState() => _SearchableSelectState<T>();
}

class _SearchableSelectState<T> extends State<SearchableSelect<T>> {
  final LayerLink _layerLink = LayerLink();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _listScroll = ScrollController();
  OverlayEntry? _overlayEntry;
  String _query = '';
  int _highlightedIndex = 0;
  bool _opensAbove = false;
  bool _autoOpenScheduled = false;
  double _popupWidth = 280;
  double _popupMaxHeight = 304;
  double _horizontalOffset = 0;

  List<SearchableSelectOption<T>> get _filteredOptions {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.options;
    return widget.options.where((option) {
      return option.label.toLowerCase().contains(query) ||
          (option.searchText?.toLowerCase().contains(query) ?? false);
    }).toList(growable: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.autoOpen && !_autoOpenScheduled) {
      _autoOpenScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openPopup();
      });
    }
  }

  @override
  void didUpdateWidget(covariant SearchableSelect<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoOpen && !widget.autoOpen) _autoOpenScheduled = false;
  }

  @override
  void dispose() {
    final entry = _overlayEntry;
    _overlayEntry = null;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
    _searchFocus.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  void _openPopup() {
    if (!widget.enabled || _overlayEntry != null || !mounted) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final origin = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;
    final viewport = MediaQuery.sizeOf(context);
    final direction = Directionality.of(context);
    final maxDesiredHeight = math.min(widget.maxPopupHeight, 320.0);
    final aboveSpace = origin.dy - 12;
    final belowSpace = viewport.height - origin.dy - size.height - 12;
    _opensAbove = belowSpace < math.min(maxDesiredHeight, 200.0) &&
        aboveSpace > belowSpace;
    final availableSpace = _opensAbove ? aboveSpace : belowSpace;
    _popupMaxHeight = math.min(
      maxDesiredHeight,
      math.max(104.0, availableSpace - 8),
    );

    _popupWidth = math.min(
      math.max(size.width, 260.0),
      math.max(120.0, viewport.width - 24),
    );
    final targetRight = origin.dx + size.width;
    final wantedLeft = direction == TextDirection.rtl
        ? targetRight - _popupWidth
        : origin.dx;
    final clampedLeft = wantedLeft
        .clamp(8.0, math.max(8.0, viewport.width - _popupWidth - 8))
        .toDouble();
    _horizontalOffset = direction == TextDirection.rtl
        ? clampedLeft + _popupWidth - targetRight
        : clampedLeft - origin.dx;

    final selectedIndex =
        _filteredOptions.indexWhere((option) => option.value == widget.value);
    _highlightedIndex = selectedIndex < 0 ? 0 : selectedIndex;
    _query = '';

    _overlayEntry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _overlayEntry != null) _searchFocus.requestFocus();
    });
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final targetAnchor = _opensAbove
        ? (rtl ? Alignment.topRight : Alignment.topLeft)
        : (rtl ? Alignment.bottomRight : Alignment.bottomLeft);
    final followerAnchor = _opensAbove
        ? (rtl ? Alignment.bottomRight : Alignment.bottomLeft)
        : (rtl ? Alignment.topRight : Alignment.topLeft);
    final results = _filteredOptions;
    final desiredHeight = math.min(
      _popupMaxHeight,
      64.0 + math.max(1, math.min(results.length, 5)) * 48.0,
    );

    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: targetAnchor,
            followerAnchor: followerAnchor,
            offset: Offset(_horizontalOffset, _opensAbove ? -8 : 8),
            child: TapRegion(
              groupId: this,
              onTapOutside: (_) => _closePopup(),
              child: Material(
                key: ValueKey('searchable-select-popup-' + widget.id),
                elevation: 14,
                color: Theme.of(context).colorScheme.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: SizedBox(
                  width: _popupWidth,
                  height: desiredHeight,
                  child: Focus(
                    onKeyEvent: _handlePopupKey,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                          child: TextField(
                            key: ValueKey('searchable-select-search-' + widget.id),
                            focusNode: _searchFocus,
                            onChanged: (value) {
                              _query = value;
                              _highlightedIndex = 0;
                              if (_listScroll.hasClients) {
                                _listScroll.jumpTo(0);
                              }
                              _overlayEntry?.markNeedsBuild();
                            },
                            decoration: InputDecoration(
                              hintText: widget.searchHint,
                              prefixIcon: const Icon(Icons.search_rounded),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: results.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      widget.emptyLabel,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  key: ValueKey(
                                    'searchable-select-list-' + widget.id,
                                  ),
                                  controller: _listScroll,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  itemCount: results.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 2),
                                  itemBuilder: (context, index) {
                                    final option = results[index];
                                    final selected =
                                        option.value == widget.value;
                                    final highlighted =
                                        index == _highlightedIndex;
                                    return SizedBox(
                                      height: 46,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                        child: Material(
                                          color: highlighted || selected
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primaryContainer
                                                  .withValues(alpha: 0.55)
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: InkWell(
                                            key: ValueKey(
                                              'searchable-select-option-'
                                              '${widget.id}-$index',
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            onTap: () => _select(option),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsetsDirectional
                                                      .only(start: 12, end: 10),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      option.label,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (selected)
                                                    Icon(
                                                      Icons.check_rounded,
                                                      size: 18,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  KeyEventResult _handlePopupKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final options = _filteredOptions;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _closePopup();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (options.isNotEmpty) {
        _highlightedIndex =
            (_highlightedIndex + 1).clamp(0, options.length - 1);
        _scrollHighlightedIntoView();
        _overlayEntry?.markNeedsBuild();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (options.isNotEmpty) {
        _highlightedIndex =
            (_highlightedIndex - 1).clamp(0, options.length - 1);
        _scrollHighlightedIntoView();
        _overlayEntry?.markNeedsBuild();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        options.isNotEmpty) {
      final index = _highlightedIndex.clamp(0, options.length - 1);
      _select(options[index]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrollHighlightedIntoView() {
    if (!_listScroll.hasClients) return;
    final target = _highlightedIndex * 48.0;
    final maxScroll = _listScroll.position.maxScrollExtent;
    _listScroll.animateTo(
      target.clamp(0.0, maxScroll),
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
    );
  }

  void _select(SearchableSelectOption<T> option) {
    _closePopup();
    widget.onChanged(option.value);
  }

  void _closePopup() {
    final entry = _overlayEntry;
    if (entry == null) return;
    _overlayEntry = null;
    entry.remove();
    entry.dispose();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.options
        .where((option) => option.value == widget.value)
        .firstOrNull;
    return TapRegion(
      groupId: this,
      onTapOutside: (_) => _closePopup(),
      child: CompositedTransformTarget(
        link: _layerLink,
        child: Semantics(
          button: true,
          enabled: widget.enabled,
          expanded: _overlayEntry != null,
          label: widget.label,
          value: selected?.label,
          child: InkWell(
            key: ValueKey('searchable-select-trigger-' + widget.id),
            onTap: widget.enabled
                ? () => _overlayEntry == null ? _openPopup() : _closePopup()
                : null,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              isEmpty: selected == null,
              isFocused: _overlayEntry != null,
              decoration: InputDecoration(
                labelText: widget.label,
                enabled: widget.enabled,
                isDense: true,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selected?.label ?? widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _overlayEntry == null
                        ? Icons.expand_more_rounded
                        : Icons.expand_less_rounded,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
