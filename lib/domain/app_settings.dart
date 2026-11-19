class AppSettings {
  const AppSettings({
    required this.darkMode,
    required this.languageCode,
    this.businessName = '',
    this.currencyCode = 'USD',
    this.accountingCurrencyConfigured = false,
    this.desktopSidebarCollapsed = false,
    this.defaultTaxRateBasisPoints = 0,
  });

  static const defaults = AppSettings(
    darkMode: false,
    languageCode: 'en',
  );

  final bool darkMode;
  final String languageCode;
  final String businessName;
  final String currencyCode;
  final bool accountingCurrencyConfigured;
  final bool desktopSidebarCollapsed;
  final int defaultTaxRateBasisPoints;

  AppSettings copyWith({
    bool? darkMode,
    String? languageCode,
    String? businessName,
    String? currencyCode,
    bool? accountingCurrencyConfigured,
    bool? desktopSidebarCollapsed,
    int? defaultTaxRateBasisPoints,
  }) => AppSettings(
        darkMode: darkMode ?? this.darkMode,
        languageCode: languageCode ?? this.languageCode,
        businessName: businessName ?? this.businessName,
        currencyCode: currencyCode ?? this.currencyCode,
        accountingCurrencyConfigured: accountingCurrencyConfigured ?? this.accountingCurrencyConfigured,
        desktopSidebarCollapsed: desktopSidebarCollapsed ?? this.desktopSidebarCollapsed,
        defaultTaxRateBasisPoints: defaultTaxRateBasisPoints ?? this.defaultTaxRateBasisPoints,
      );
}
