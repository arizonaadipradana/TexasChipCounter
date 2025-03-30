import 'dart:async';
import 'dart:math' as Math;

import '../models/game_model.dart';
import '../services/game_service_core.dart';
import '../utils/socket_manager.dart';

/// Handles synchronization of game state between clients
class GameSyncManager {
  // Singleton instance
  static final GameSyncManager _instance = GameSyncManager._internal();
  factory GameSyncManager() => _instance;
  GameSyncManager._internal();

  // Track state versions by game ID
  final Map<String, int> _gameStateVersions = {};

  // Track last state refresh time by game ID
  final Map<String, DateTime> _lastRefreshTimes = {};

  // Track sync operations in progress
  final Map<String, bool> _syncInProgress = {};

  // Track errors per game
  final Map<String, int> _errorCounts = {};

  // Maximum allowed errors before forcing reconnection
  static const int MAX_ERRORS_BEFORE_RECONNECT = 3;

  // Minimum time between refreshes in seconds
  static const int MIN_REFRESH_INTERVAL_SECONDS = 2;

  /// Initialize sync for a game
  void initializeSync(String gameId) {
    _gameStateVersions[gameId] = 0;
    _lastRefreshTimes[gameId] = DateTime.now();
    _syncInProgress[gameId] = false;
    _errorCounts[gameId] = 0;

    print('Initialized sync for game: $gameId');
  }

  /// Synchronize game state
  Future<bool> synchronizeState(
      String gameId,
      String authToken,
      GameService gameService,
      SocketManager socketManager,
      Function(GameModel) onStateUpdated
      ) async {
    // Don't allow multiple sync operations for the same game
    if (_syncInProgress[gameId] == true) {
      print('Sync already in progress for game: $gameId, skipping');
      return false;
    }

    // Check if it's too soon to refresh
    final lastRefresh = _lastRefreshTimes[gameId] ?? DateTime.now().subtract(Duration(days: 1));
    final timeSinceLastRefresh = DateTime.now().difference(lastRefresh).inSeconds;

    if (timeSinceLastRefresh < MIN_REFRESH_INTERVAL_SECONDS) {
      print('Last refresh was only ${timeSinceLastRefresh}s ago, skipping');
      return false;
    }

    // Mark sync in progress
    _syncInProgress[gameId] = true;

    try {
      print('Synchronizing state for game: $gameId');

      // Get latest game state from server
      final result = await gameService.getGame(gameId, authToken);

      if (result['success']) {
        final gameModel = result['game'] as GameModel;

        // Update state version
        _gameStateVersions[gameId] = (_gameStateVersions[gameId] ?? 0) + 1;

        // Update last refresh time
        _lastRefreshTimes[gameId] = DateTime.now();

        // Reset error count
        _errorCounts[gameId] = 0;

        // Notify about state update
        onStateUpdated(gameModel);

        // Broadcast update to all clients to ensure everyone has the same state
        socketManager.emit('game_action', {
          'gameId': gameId,
          'action': 'game_update',
          'game': gameModel.toJson(),
          'stateVersion': _gameStateVersions[gameId],
          'timestamp': DateTime.now().toIso8601String(),
          'source': 'sync_manager'
        });

        print('State synchronized successfully for game: $gameId (version: ${_gameStateVersions[gameId]})');
        return true;
      } else {
        // Increment error count
        _errorCounts[gameId] = (_errorCounts[gameId] ?? 0) + 1;

        print('Failed to sync state: ${result['message'] ?? 'Unknown error'}');

        // If too many errors, force reconnection
        if (_errorCounts[gameId]! >= MAX_ERRORS_BEFORE_RECONNECT) {
          print('Too many errors, forcing reconnection');
          socketManager.forceReconnect();
          _errorCounts[gameId] = 0;
        }

        return false;
      }
    } catch (e) {
      // Increment error count
      _errorCounts[gameId] = (_errorCounts[gameId] ?? 0) + 1;

      print('Error synchronizing state: $e');
      return false;
    } finally {
      // Clear sync in progress
      _syncInProgress[gameId] = false;
    }
  }

  /// Check if sync is needed
  bool isSyncNeeded(String gameId) {
    // If we don't have record of this game, sync is needed
    if (!_lastRefreshTimes.containsKey(gameId)) {
      return true;
    }

    // Check how long since last refresh
    final lastRefresh = _lastRefreshTimes[gameId]!;
    final timeSinceLastRefresh = DateTime.now().difference(lastRefresh).inSeconds;

    // If it's been more than 10 seconds, sync is needed
    return timeSinceLastRefresh > 10;
  }

  /// Start periodic sync for a game
  Timer startPeriodicSync(
      String gameId,
      String authToken,
      GameService gameService,
      SocketManager socketManager,
      Function(GameModel) onStateUpdated
      ) {
    // Init if not already done
    if (!_gameStateVersions.containsKey(gameId)) {
      initializeSync(gameId);
    }

    // Start a timer to sync every 15 seconds
    return Timer.periodic(Duration(seconds: 15), (timer) {
      // Only sync if needed
      if (isSyncNeeded(gameId)) {
        synchronizeState(gameId, authToken, gameService, socketManager, onStateUpdated);
      }
    });
  }

  /// Force immediate sync
  Future<bool> forceSyncNow(
      String gameId,
      String authToken,
      GameService gameService,
      SocketManager socketManager,
      Function(GameModel) onStateUpdated
      ) async {
    // Reset timestamps to ensure sync happens
    _lastRefreshTimes[gameId] = DateTime.now().subtract(Duration(seconds: MIN_REFRESH_INTERVAL_SECONDS + 1));
    _syncInProgress[gameId] = false;

    // Perform sync
    return await synchronizeState(gameId, authToken, gameService, socketManager, onStateUpdated);
  }

  /// Handle a game state change from any source
  void handleGameStateChange(
      String gameId,
      GameModel gameModel,
      int stateVersion,
      SocketManager socketManager
      ) {
    // Update local version if newer
    final currentVersion = _gameStateVersions[gameId] ?? 0;

    if (stateVersion > currentVersion) {
      print('Updating local state version from $currentVersion to $stateVersion');
      _gameStateVersions[gameId] = stateVersion;
      _lastRefreshTimes[gameId] = DateTime.now();
    }
  }

  /// Clean up resources for a game
  void cleanupGame(String gameId) {
    _gameStateVersions.remove(gameId);
    _lastRefreshTimes.remove(gameId);
    _syncInProgress.remove(gameId);
    _errorCounts.remove(gameId);

    print('Cleaned up sync resources for game: $gameId');
  }
}