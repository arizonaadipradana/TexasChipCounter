import 'dart:async';
import '../models/game_model.dart';

/// Manages state for the game service including caching,
/// refresh tracking, and other state-related functionality
class GameServiceState {
  // Cached data for game models to reduce API calls
  static final Map<String, GameModel> _gameCache = {};

  // Refresh timestamps to track when data was last fetched
  static final Map<String, DateTime> _lastRefreshTimes = {};

  // Whether a refresh is in progress for a specific game ID
  static final Map<String, bool> _refreshInProgress = {};

  // Default stale time in seconds before data should be refreshed
  static const int _defaultStaleTimeSeconds = 5;

  /// Store a game model in cache with current timestamp
  static void cacheGame(String gameId, GameModel game) {
    _gameCache[gameId] = game;
    _lastRefreshTimes[gameId] = DateTime.now();
  }

  /// Get a cached game if available and not stale
  static GameModel? getCachedGame(String gameId, {int staleTimeSeconds = _defaultStaleTimeSeconds}) {
    final cached = _gameCache[gameId];
    final lastRefresh = _lastRefreshTimes[gameId];

    // If no cached data or no timestamp, it's not available
    if (cached == null || lastRefresh == null) {
      return null;
    }

    // Check if data is stale
    final now = DateTime.now();
    final staleDuration = Duration(seconds: staleTimeSeconds);
    if (now.difference(lastRefresh) > staleDuration) {
      return null; // Data is stale
    }

    return cached;
  }

  /// Mark a refresh operation as in progress for a game
  static bool markRefreshInProgress(String gameId) {
    if (_refreshInProgress[gameId] == true) {
      return false; // Already in progress
    }

    _refreshInProgress[gameId] = true;
    return true;
  }

  /// Mark a refresh operation as complete
  static void markRefreshComplete(String gameId) {
    _refreshInProgress[gameId] = false;
    _lastRefreshTimes[gameId] = DateTime.now();
  }

  /// Check if a refresh is needed for a game
  static bool isRefreshNeeded(String gameId, {int staleTimeSeconds = _defaultStaleTimeSeconds}) {
    final lastRefresh = _lastRefreshTimes[gameId];

    // If no timestamp, refresh is needed
    if (lastRefresh == null) {
      return true;
    }

    // Check if data is stale
    final now = DateTime.now();
    final staleDuration = Duration(seconds: staleTimeSeconds);
    return now.difference(lastRefresh) > staleDuration;
  }

  /// Clear cache for a specific game
  static void clearCache(String gameId) {
    _gameCache.remove(gameId);
    _lastRefreshTimes.remove(gameId);
    _refreshInProgress.remove(gameId);
  }

  /// Clear all cached data
  static void clearAllCache() {
    _gameCache.clear();
    _lastRefreshTimes.clear();
    _refreshInProgress.clear();
  }

  /// Get the last refresh time for a game
  static DateTime? getLastRefreshTime(String gameId) {
    return _lastRefreshTimes[gameId];
  }

  /// Set up a periodic refresh for a game
  static Timer setupPeriodicRefresh(String gameId, Function() refreshFunction, {int intervalSeconds = 10}) {
    return Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      if (isRefreshNeeded(gameId)) {
        refreshFunction();
      }
    });
  }
}