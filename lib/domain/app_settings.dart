class AppSettings {
  const AppSettings({
    required this.darkMode,
    required this.languageCode,
    this.businessName = '',
    this.businessType = 'retail',
    this.countryCode = '',
    this.currencyCode = 'USD',
    this.marketDisplayCurrencyCode = 'TOMAN',
    this.accountingCurrencyConfigured = false,
    this.setupCompleted = false,
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
  final String businessType;
  final String countryCode;
  final String currencyCode;
  final String marketDisplayCurrencyCode;
  final bool accountingCurrencyConfigured;
  final bool setupCompleted;
  final bool desktopSidebarCollapsed;
  final int defaultTaxRateBasisPoints;

  AppSettings copyWith({
    bool? darkMode,
    String? languageCode,
    String? businessName,
    String? businessType,
    String? countryCode,
    String? currencyCode,
    String? marketDisplayCurrencyCode,
    bool? accountingCurrencyConfigured,
    bool? setupCompleted,
    bool? desktopSidebarCollapsed,
    int? defaultTaxRateBasisPoints,
  }) => AppSettings(
        darkMode: darkMode ?? this.darkMode,
        languageCode: languageCode ?? this.languageCode,
        businessName: businessName ?? this.businessName,
        businessType: businessType ?? this.businessType,
        countryCode: countryCode ?? this.countryCode,
        currencyCode: currencyCode ?? this.currencyCode,
        marketDisplayCurrencyCode: marketDisplayCurrencyCode ?? this.marketDisplayCurrencyCode,
        accountingCurrencyConfigured: accountingCurrencyConfigured ?? this.accountingCurrencyConfigured,
        setupCompleted: setupCompleted ?? this.setupCompleted,
        desktopSidebarCollapsed: desktopSidebarCollapsed ?? this.desktopSidebarCollapsed,
        defaultTaxRateBasisPoints: defaultTaxRateBasisPoints ?? this.defaultTaxRateBasisPoints,
      );
}
