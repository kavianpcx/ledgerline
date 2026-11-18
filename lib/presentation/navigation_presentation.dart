enum LedgerNavigationPresentation {
  windowsSidebar,
  tabletRail,
  mobileBottomBar,
}

/// Keeps the desktop navigation contract independent of window width.
LedgerNavigationPresentation navigationPresentationFor({
  required bool windowsDesktop,
  required double availableWidth,
}) {
  if (windowsDesktop) return LedgerNavigationPresentation.windowsSidebar;
  if (availableWidth >= 900) return LedgerNavigationPresentation.tabletRail;
  return LedgerNavigationPresentation.mobileBottomBar;
}

/// Expanded by default on wide windows; medium windows stay compact unless the
/// user explicitly expands the sidebar. Very narrow windows remain compact.
bool desktopSidebarExpandedFor({
  required double availableWidth,
  required bool collapsedPreference,
  bool expandedAtMediumWidth = false,
}) {
  if (collapsedPreference || availableWidth < 760) return false;
  return availableWidth >= 1180 || expandedAtMediumWidth;
}
