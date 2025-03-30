class AppConfig {
  // App name
  static const String appName = 'Nyanguni Kancane';

  // App version
  static const String appVersion = '1.0.0';

  // Chip to rupiah conversion rate
  static const int chipToRupiahRate = 500; // 1 chip = 500 rupiah

  // Default game settings
  static const int defaultSmallBlind = 5;
  static const int defaultBigBlind = 10;

  // Minimum and maximum values
  static const int minTopUp = 10; // Minimum top-up amount in chips
  static const int maxTopUp = 1000; // Maximum top-up amount in chips

  // Time constants (in seconds)
  static const int turnTimeout = 30; // Time limit for a player's turn
  static const int gameActivityTimeout = 3600; // Auto-end inactive games after 1 hour

  // App theme settings
  static const bool useDarkMode = false;
  static const String primaryColorHex = '#2196F3'; // Blue
  static const String secondaryColorHex = '#4CAF50'; // Green
}