class ApiConfig {
  // Base URL for API requests
  // Fix the URL format by adding the http:// protocol
  static const String baseUrl = 'https://52e1-2001-448a-4026-126c-a03b-f1e6-2891-e38f.ngrok-free.app';

  // API endpoints
  static const String loginEndpoint = '/api/users/login';
  static const String registerEndpoint = '/api/users/register';
  static const String userEndpoint = '/api/users/me';
  static const String topUpEndpoint = '/api/users/topup';
  static const String gamesEndpoint = '/api/games';
  static const String transactionsEndpoint = '/api/transactions';

  // API timeout duration in seconds
  static const int timeoutDuration = 10;
}