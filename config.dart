class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://BACKEND-DOMAININIZ.example',
  );

  // 299,00 TL tek seferlik Premium.
  static const int lifetimePremiumPriceKurus = 29900;
}
