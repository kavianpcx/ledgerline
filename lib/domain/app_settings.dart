class AppSettings {
  const AppSettings({
    required this.darkMode,
    required this.languageCode,
    this.businessName = '',
    this.currencyCode = 'USD',
  });

  static const defaults = AppSettings(
    darkMode: false,
    languageCode: 'en',
  );

  final bool darkMode;
  final String languageCode;
  final String businessName;
  final String currencyCode;

  AppSettings copyWith({
    bool? darkMode,
    String? languageCode,
    String? businessName,
    String? currencyCode,
  }) => AppSettings(
        darkMode: darkMode ?? this.darkMode,
        languageCode: languageCode ?? this.languageCode,
        businessName: businessName ?? this.businessName,
        currencyCode: currencyCode ?? this.currencyCode,
      );
}
