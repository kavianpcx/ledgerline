class AppSettings {
  const AppSettings({
    required this.darkMode,
    required this.languageCode,
    this.businessName = '',
    this.currencyCode = 'USD',
    this.desktopSidebarCollapsed = false,
  });

  static const defaults = AppSettings(
    darkMode: false,
    languageCode: 'en',
  );

  final bool darkMode;
  final String languageCode;
  final String businessName;
  final String currencyCode;
  final bool desktopSidebarCollapsed;

  AppSettings copyWith({
    bool? darkMode,
    String? languageCode,
    String? businessName,
    String? currencyCode,
    bool? desktopSidebarCollapsed,
  }) => AppSettings(
        darkMode: darkMode ?? this.darkMode,
        languageCode: languageCode ?? this.languageCode,
        businessName: businessName ?? this.businessName,
        currencyCode: currencyCode ?? this.currencyCode,
        desktopSidebarCollapsed: desktopSidebarCollapsed ?? this.desktopSidebarCollapsed,
      );
}
