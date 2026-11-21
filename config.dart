class AppConfig {
  // Üretimde kendi HTTPS backend adresinizle değiştirin.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://BACKEND-DOMAININIZ.example',
  );
  static const int lifetimePremiumPriceKurus = 29900;
}
