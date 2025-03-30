import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as Math;
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/game_model.dart';
import '../utils/game_sync_manager.dart';
import '../utils/socket_manager.dart';
import 'auth_service.dart';
import 'game_service_api.dart';
import 'game_service_events.dart';
import 'game_service_state.dart';

/// Core GameService class with improved sync
class GameService {
  // Use the singleton socket manager instead of creating a socket directly
  final SocketManager _socketManager = SocketManager();

  // Throttle timers to prevent excessive API calls or emissions
  Timer? _actionThrottleTimer;
  Timer? _refreshThrottleTimer;
  Timer? _emitThrottleTimer;

  // Map to store game ID lookups (short ID to full ID)
  static final Map<String, String> _gameIdMap = {};

  // Keep track of active game rooms
  final Set<String> _activeGames = {};

  // Periodic state sync timer
  Timer? _stateSyncTimer;

  // Last state refresh time per game
  final Map<String, DateTime> _lastRefreshTimes = {};

  // Callbacks for game updates
  final Map<String, List<Function(dynamic)>> _gameUpdateCallbacks = {};

  // Special game sync manager for critical state changes
  final GameSyncManager _syncManager = GameSyncManager();

  // Timers for periodic sync per game
  final Map<String, Timer> _syncTimers = {};

  bool? get isSocketConnected {
    return _socketManager.isConnected;
  }

  static void registerGameId(String fullId) {
    final shortId = fullId.substring(0, Math.min(6, fullId.length)).toUpperCase();
    _gameIdMap[shortId] = fullId;
    print('Registered game ID: $shortId -> $fullId');
  }

  /// Look up full game ID from short ID
  static String? getFullGameId(String shortId) {
    return _gameIdMap[shortId.toUpperCase()];
  }

  /// Clear game ID cache
  static void clearGameIdCache() {
    _gameIdMap.clear();
    print('Game ID cache cleared');
  }

  /// Initialize socket with enhanced state handling
  void initSocket(String authToken, {String? userId}) {
    _socketManager.initSocket(authToken, userId: userId);

    // Set a state change callback
    _socketManager.setStateChangeCallback(_handleSignificantStateChange);

    // Start periodic state sync for all active games
    _startPeriodicStateSync(authToken);
  }

  // Handle significant game state changes detected by socket manager
  void _handleSignificantStateChange(Map<String, dynamic> data) {
    final gameId = data['gameId'];
    if (gameId != null && _gameUpdateCallbacks.containsKey(gameId)) {
      // Notify all callbacks for this game
      for (final callback in _gameUpdateCallbacks[gameId]!) {
        callback(data);
      }
    }
  }

  // Start a periodic state synchronization for all active games
  void _startPeriodicStateSync(String authToken) {
    // Cancel existing timer if any
    _stateSyncTimer?.cancel();

    // Check state every 3 seconds
    _stateSyncTimer = Timer.periodic(Duration(seconds: 3), (timer) {
      // For each active game, check if we need to refresh state
      for (final gameId in _activeGames) {
        final lastRefresh = _lastRefreshTimes[gameId] ?? DateTime.now().subtract(Duration(seconds: 10));
        final timeSinceLastRefresh = DateTime.now().difference(lastRefresh);

        // If it's been more than 5 seconds since last refresh, get latest state
        if (timeSinceLastRefresh.inSeconds > 5) {
          _refreshGameState(gameId, authToken);
        }
      }
    });
  }

  // Refresh game state from server and broadcast to all clients
  Future<void> _refreshGameState(String gameId, String authToken) async {
    try {
      print('Performing periodic state refresh for game: $gameId');

      // Mark refresh time first to prevent multiple simultaneous requests
      _lastRefreshTimes[gameId] = DateTime.now();

      // Get game state from server
      final result = await getGame(gameId, authToken);

      if (result['success']) {
        // Update last refresh time
        _lastRefreshTimes[gameId] = DateTime.now();

        // Broadcast state to all clients
        _socketManager.emit('game_action', {
          'gameId': gameId,
          'action': 'game_update',
          'game': (result['game'] as GameModel).toJson(),
          'timestamp': DateTime.now().toIso8601String(),
          'source': 'periodic_refresh'
        });
      }
    } catch (e) {
      print('Error refreshing game state: $e');
    }
  }

  /// Join a game room and track it
  void joinGameRoom(String gameId) {
    print('Joining game room with enhanced state handling: $gameId');
    _socketManager.joinGameRoom(gameId);

    // Track this as an active game
    _activeGames.add(gameId);

    // Initialize sync manager for this game
    _syncManager.initializeSync(gameId);

    // Always refresh state on join
    if (_socketManager.authToken != null) {
      getGame(gameId, _socketManager.authToken!).then((result) {
        if (result['success']) {
          // Force a state update
          _socketManager.emit('game_action', {
            'gameId': gameId,
            'action': 'game_update',
            'game': (result['game'] as GameModel).toJson(),
            'timestamp': DateTime.now().toIso8601String(),
            'source': 'join_refresh'
          });
        }
      });
    }
  }

  /// Leave a game room and clean up
  void leaveGameRoom(String gameId) {
    print('Leaving game room: $gameId');
    _socketManager.leaveGameRoom(gameId);

    // Remove from active games
    _activeGames.remove(gameId);

    // Clean up callbacks
    _gameUpdateCallbacks.remove(gameId);

    // Remove refresh time
    _lastRefreshTimes.remove(gameId);

    // Clean up sync timers
    _syncTimers[gameId]?.cancel();
    _syncTimers.remove(gameId);

    // Clean up sync manager
    _syncManager.cleanupGame(gameId);
  }

  /// Add a callback for game updates
  void addGameUpdateCallback(String gameId, Function(dynamic) callback) {
    if (!_gameUpdateCallbacks.containsKey(gameId)) {
      _gameUpdateCallbacks[gameId] = [];
    }

    _gameUpdateCallbacks[gameId]!.add(callback);
  }

  /// Force a state synchronization from server with special implementation
  /// for fixing UI update issues
  Future<void> forceStateSynchronization(String gameId, String authToken) async {
    try {
      print('Forcing comprehensive state synchronization for game: $gameId');

      // Cancel any pending throttle timer
      _refreshThrottleTimer?.cancel();

      // Use the new comprehensive sync method
      final result = await GameServiceApi.synchronizeGameState(
          gameId,
          authToken,
          _socketManager,
          forceBroadcast: true
      );

      if (result['success']) {
        _lastRefreshTimes[gameId] = DateTime.now();

        // Force a UI refresh for all clients
        await GameServiceApi.forceClientUIRefresh(
            gameId,
            result['game'] as GameModel,
            _socketManager
        );

        // Start a sync timer if not already started
        if (!_syncTimers.containsKey(gameId)) {
          _syncTimers[gameId] = _syncManager.startPeriodicSync(
              gameId,
              authToken,
              this,
              _socketManager,
                  (GameModel gameModel) {
                // When state updates, broadcast to any local callbacks
                if (_gameUpdateCallbacks.containsKey(gameId)) {
                  for (final callback in _gameUpdateCallbacks[gameId]!) {
                    callback({
                      'action': 'game_update',
                      'gameId': gameId,
                      'game': gameModel.toJson(),
                      'timestamp': DateTime.now().toIso8601String(),
                      'source': 'sync_timer'
                    });
                  }
                }
              }
          );
        }

        print('State synchronization completed for game: $gameId');
      } else {
        print('Failed to synchronize state: ${result['message']}');

        // Force socket reconnection as a fallback
        _socketManager.forceReconnect();
      }
    } catch (e) {
      print('Error forcing state synchronization: $e');

      // Force socket reconnection on error
      _socketManager.forceReconnect();
    }
  }

  /// Get active games - delegated to API module
  Future<Map<String, dynamic>> getActiveGames(String authToken) async {
    return await GameServiceApi.getActiveGames(authToken);
  }

  /// Get user's games - delegated to API module
  Future<Map<String, dynamic>> getUserGames(
      String authToken, {
        String? status,
      }) async {
    return await GameServiceApi.getUserGames(authToken, status: status);
  }

  /// Force a reconnection of the socket
  void forceReconnect() {
    _socketManager.forceReconnect();
  }

  /// For cleaning up resources
  void dispose() {
    _stateSyncTimer?.cancel();
    _gameUpdateCallbacks.clear();
    _activeGames.clear();
    _lastRefreshTimes.clear();

    // Clean up sync timers
    for (final timer in _syncTimers.values) {
      timer.cancel();
    }
    _syncTimers.clear();
  }

  /// Get game details with improved error handling and throttling
  Future<Map<String, dynamic>> getGame(
      String gameId,
      String authToken,
      ) async {
    return await GameServiceApi.getGame(gameId, authToken);
  }

  // Re-expose API methods from the API module
  Future<Map<String, dynamic>> validateGameId(
      String shortId, String authToken) async {
    return await GameServiceApi.validateGameId(shortId, authToken);
  }

  Future<Map<String, dynamic>> createGame(
      String name,
      int smallBlind,
      int bigBlind,
      String authToken,
      ) async {
    return await GameServiceApi.createGame(name, smallBlind, bigBlind, authToken);
  }

  Future<Map<String, dynamic>> joinGame(
      String shortId, String authToken) async {
    return await GameServiceApi.joinGame(shortId, authToken, _socketManager, notifyPlayerJoined);
  }

  Future<Map<String, dynamic>> startGame(
      String gameId,
      String authToken,
      ) async {
    return await GameServiceApi.startGame(gameId, authToken, _socketManager);
  }

  Future<Map<String, dynamic>> endGame(
      String gameId,
      String authToken,
      ) async {
    return await GameServiceApi.endGame(gameId, authToken, _socketManager);
  }

  /// Game action with improved sync and reliability
  Future<Map<String, dynamic>> gameAction(
      String gameId,
      String actionType,
      String authToken,
      {int? amount}
      ) async {
    final result = await GameServiceApi.gameAction(
        gameId,
        actionType,
        authToken,
        _socketManager,
        _lastRefreshTimes,
        _broadcastActionWithRetries,
        amount: amount
    );

    // Force a state refresh after gameplay actions
    if (result['success']) {
      // Delay to allow server to process the action
      Future.delayed(Duration(milliseconds: 300), () {
        // Use the sync manager for immediate reliability
        _syncManager.forceSyncNow(
            gameId,
            authToken,
            this,
            _socketManager,
                (GameModel gameModel) {
              // When state updates, broadcast to any local callbacks
              if (_gameUpdateCallbacks.containsKey(gameId)) {
                for (final callback in _gameUpdateCallbacks[gameId]!) {
                  callback({
                    'action': 'force_ui_refresh',
                    'gameId': gameId,
                    'game': gameModel.toJson(),
                    'timestamp': DateTime.now().toIso8601String(),
                    'source': 'post_action_sync'
                  });
                }
              }
            }
        );
      });
    }

    return result;
  }

  void _broadcastActionWithRetries(String gameId, String action, int? amount, GameModel game) {
    GameServiceEvents.broadcastActionWithRetries(gameId, action, amount, game, _socketManager);
  }

  // Events handling - delegated to events module
  void listenForAllGameUpdates(String gameId, Function(dynamic) onUpdate) {
    GameServiceEvents.listenForAllGameUpdates(gameId, onUpdate, _socketManager, _activeGames,
        _lastRefreshTimes, _gameUpdateCallbacks, this);

    // Listen for the special force_ui_refresh event
    _socketManager.on('force_ui_refresh', (data) {
      if (data['gameId'] == gameId) {
        print('Received force_ui_refresh event');
        onUpdate(data);
      }
    });
  }

  void cleanupGameListeners() {
    GameServiceEvents.clearAllGameEventListeners(_socketManager);
    _socketManager.clearListeners('force_ui_refresh');
  }

  void listenForPlayerUpdates(
      Function(GameModel) onPlayerUpdate,
      [Function(String, String)? onKicked]) {
    GameServiceEvents.listenForPlayerUpdates(onPlayerUpdate, _socketManager, onKicked);
  }

  void notifyPlayerJoined(String gameId, GameModel updatedGame) {
    _emitThrottleTimer?.cancel();
    _emitThrottleTimer = Timer(Duration(milliseconds: 250), () {
      _socketManager.emit('game_action', {
        'gameId': gameId,
        'action': 'player_joined',
        'game': updatedGame.toJson(),
        'timestamp': DateTime.now().toIso8601String()
      });
    });
  }

  void notifyPlayerRemoved(
      String gameId, GameModel updatedGame, String removedUserId) {
    _socketManager.emit('game_action', {
      'gameId': gameId,
      'action': 'player_kicked',
      'kickedUserId': removedUserId,
      'game': updatedGame.toJson(),
      'timestamp': DateTime.now().toIso8601String(),
      'removedBy': _socketManager.userId
    });
  }

  void notifyPlayerQuitting(String gameId, GameModel updatedGame) {
    _socketManager.emit('game_action', {
      'gameId': gameId,
      'action': 'player_left',
      'userId': _socketManager.userId,
      'game': updatedGame.toJson(),
      'timestamp': DateTime.now().toIso8601String()
    });
  }

  /// Helper method to emit events with more control
  void emit(String event, dynamic data) {
    GameServiceEvents.emit(event, data, _socketManager);
  }

  Future<void> resyncGameState(String gameId, String authToken) async {
    await GameServiceEvents.resyncGameState(gameId, authToken, _socketManager, this);
  }

  Future<Map<String, dynamic>> checkSocketStatus(String gameId) async {
    return GameServiceEvents.checkSocketStatus(gameId, _socketManager);
  }

  SocketManager getSocketManager() {
    return _socketManager;
  }
}