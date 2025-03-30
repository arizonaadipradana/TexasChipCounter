import 'dart:async';
import 'dart:math' as Math;

import '../models/game_model.dart';
import '../utils/socket_manager.dart';

/// Handles events and real-time communication for game service
class GameServiceEvents {
  // Track processed events to avoid duplicates
  static final Set<String> _processedEvents = {};

  // Track game state versions
  static final Map<String, int> _gameStateVersions = {};

  /// Broadcast game action with retries for reliability
  static void broadcastActionWithRetries(String gameId, String action,
      int? amount, GameModel game, SocketManager socketManager) {
    // Create a unique event ID for deduplication
    final eventId = '${gameId}_${action}_${DateTime.now().millisecondsSinceEpoch}';

    // Skip if already processed recently
    if (_processedEvents.contains(eventId)) {
      print('Skipping duplicate broadcast: $eventId');
      return;
    }

    // Add to processed events and schedule cleanup
    _processedEvents.add(eventId);
    Future.delayed(Duration(seconds: 5), () {
      _processedEvents.remove(eventId);
    });

    // Increment state version for this game
    _gameStateVersions[gameId] = (_gameStateVersions[gameId] ?? 0) + 1;
    final stateVersion = _gameStateVersions[gameId]!;

    // Immediately send multiple event types for redundancy

    // 1. Turn changed event - This is critical for UI updates
    socketManager.emit('game_action', {
      'gameId': gameId,
      'action': 'turn_changed',
      'previousPlayerIndex': game.currentPlayerIndex > 0 ? game
          .currentPlayerIndex - 1 : game.players.length - 1,
      'currentPlayerIndex': game.currentPlayerIndex,
      'game': game.toJson(),
      'stateVersion': stateVersion,
      'timestamp': DateTime.now().toIso8601String()
    });

    // 2. Game action event
    socketManager.emit('game_action', {
      'gameId': gameId,
      'action': 'game_action_performed',
      'actionType': action,
      'amount': amount,
      'previousPlayerIndex': game.currentPlayerIndex > 0 ? game
          .currentPlayerIndex - 1 : game.players.length - 1,
      'currentPlayerIndex': game.currentPlayerIndex,
      'game': game.toJson(),
      'stateVersion': stateVersion,
      'timestamp': DateTime.now().toIso8601String()
    });

    // 3. General game update
    socketManager.emit('game_action', {
      'gameId': gameId,
      'action': 'game_update',
      'game': game.toJson(),
      'stateVersion': stateVersion,
      'timestamp': DateTime.now().toIso8601String()
    });

    // 4. Force UI refresh event
    socketManager.emit('game_action', {
      'gameId': gameId,
      'action': 'force_ui_refresh',
      'game': game.toJson(),
      'stateVersion': stateVersion,
      'timestamp': DateTime.now().toIso8601String()
    });

    // Schedule multiple retries with increasing delays
    for (int i = 1; i <= 5; i++) {
      Future.delayed(Duration(milliseconds: 200 * i), () {
        if (socketManager.isConnected) {
          // Alternate between event types for maximum coverage
          switch (i % 4) {
            case 0:
              socketManager.emit('game_action', {
                'gameId': gameId,
                'action': 'turn_changed',
                'previousPlayerIndex': game.currentPlayerIndex > 0 ? game
                    .currentPlayerIndex - 1 : game.players.length - 1,
                'currentPlayerIndex': game.currentPlayerIndex,
                'game': game.toJson(),
                'stateVersion': stateVersion,
                'timestamp': DateTime.now().toIso8601String(),
                'retry': i
              });
              break;
            case 1:
              socketManager.emit('game_action', {
                'gameId': gameId,
                'action': 'game_action_performed',
                'actionType': action,
                'amount': amount,
                'previousPlayerIndex': game.currentPlayerIndex > 0 ? game
                    .currentPlayerIndex - 1 : game.players.length - 1,
                'currentPlayerIndex': game.currentPlayerIndex,
                'game': game.toJson(),
                'stateVersion': stateVersion,
                'timestamp': DateTime.now().toIso8601String(),
                'retry': i
              });
              break;
            case 2:
              socketManager.emit('game_action', {
                'gameId': gameId,
                'action': 'game_update',
                'game': game.toJson(),
                'stateVersion': stateVersion,
                'timestamp': DateTime.now().toIso8601String(),
                'retry': i
              });
              break;
            case 3:
              socketManager.emit('game_action', {
                'gameId': gameId,
                'action': 'force_ui_refresh',
                'game': game.toJson(),
                'stateVersion': stateVersion,
                'timestamp': DateTime.now().toIso8601String(),
                'retry': i
              });
              break;
          }
        }
      });
    }

    // After all retries, request a refresh from server for final verification
    Future.delayed(Duration(milliseconds: 1500), () {
      if (socketManager.isConnected) {
        socketManager.emit('game_action', {
          'gameId': gameId,
          'action': 'request_refresh',
          'timestamp': DateTime.now().toIso8601String()
        });
      }
    });
  }

  /// Helper method to handle game events consistently
  static void _handleGameEvent(dynamic data, Function(GameModel) onUpdate,
      [Function(String, String)? onKicked]) {
    try {
      if (data != null && data['game'] != null) {
        final updatedGame = GameModel.fromJson(data['game']);

        // Call the update callback
        onUpdate(updatedGame);

        // If this is a kick event and the current user was kicked, call the kick callback
        if (onKicked != null &&
            data['action'] == 'player_kicked' &&
            data['kickedUserId'] ==
                (data['socketManager']?.userId ?? 'unknown')) {
          onKicked(updatedGame.id, data['removedBy'] ?? 'host');
        }
      }
    } catch (e) {
      print('Error processing event: $e');
    }
  }

  /// IMPORTANT: This function clears all game-related event listeners
  /// to avoid socket disconnection issues
  static void clearAllGameEventListeners(SocketManager socketManager) {
    final gameEvents = [
      'game_update',
      'game_action_performed',
      'turn_changed',
      'game_started',
      'game_ended',
      'request_refresh',
      'force_ui_refresh',
    ];

    for (final event in gameEvents) {
      socketManager.clearListeners(event);
    }
  }

  /// Listen for player join/leave events - improved with better sync
  static void listenForPlayerUpdates(
      Function(GameModel) onPlayerUpdate,
      SocketManager socketManager,
      [Function(String, String)? onKicked]) {

    print('Setting up player update listeners with enhanced event handling');

    // Clear any existing listeners to avoid duplicates
    socketManager.clearListeners('player_joined');
    socketManager.clearListeners('player_left');
    socketManager.clearListeners('player_kicked');
    socketManager.clearListeners('game_started');
    socketManager.clearListeners('game_update');
    socketManager.clearListeners('force_ui_refresh');

    // Listen for player join events
    socketManager.on('player_joined', (data) {
      print('player_joined event received: $data');
      _handleGameEvent(data, onPlayerUpdate);
    });

    // Listen for player leave events
    socketManager.on('player_left', (data) {
      print('player_left event received: $data');
      _handleGameEvent(data, onPlayerUpdate);
    });

    // Listen for player kick events
    socketManager.on('player_kicked', (data) {
      print('player_kicked event received: $data');
      _handleGameEvent(data, onPlayerUpdate, onKicked);
    });

    // Listen for game started events - with higher priority
    socketManager.on('game_started', (data) {
      print('game_started event received: $data');
      _handleGameEvent(data, onPlayerUpdate);
    });

    // Generic game update (fallback)
    socketManager.on('game_update', (data) {
      print('game_update event received: $data');
      _handleGameEvent(data, onPlayerUpdate);
    });

    // Force UI refresh event
    socketManager.on('force_ui_refresh', (data) {
      print('force_ui_refresh event received');
      _handleGameEvent(data, onPlayerUpdate);
    });
  }

  /// Listen for all game-related real-time updates with a single handler
  /// This consolidates all event handlers to prevent socket disconnection issues
  static void listenForAllGameUpdates(
      String gameId,
      Function(dynamic) onUpdate,
      SocketManager socketManager,
      Set<String> activeGames,
      Map<String, DateTime> lastRefreshTimes,
      Map<String, List<Function(dynamic)>> gameUpdateCallbacks,
      dynamic gameService) {
    print('Setting up enhanced game update listeners for: $gameId');

    // Clear any existing listeners and callbacks for this game
    clearAllGameEventListeners(socketManager);

    // Initialize or clear callbacks for this game
    if (!gameUpdateCallbacks.containsKey(gameId)) {
      gameUpdateCallbacks[gameId] = [];
    } else {
      gameUpdateCallbacks[gameId]!.clear();
    }

    // Add callback for state changes
    gameUpdateCallbacks[gameId]!.add(onUpdate);

    // Handler function that processes and deduplicates events
    void gameEventHandler(dynamic data) {
      final eventName = data['action'] ?? 'game_update';
      final eventGameId = data['gameId'];
      final timestamp = data['timestamp'] ?? DateTime.now().toIso8601String();

      // Create unique event ID for deduplication
      final eventId = '${eventGameId}_${eventName}_$timestamp';

      // Only process events for our game
      if (eventGameId != gameId) return;

      // Skip if already processed recently (except for force_ui_refresh)
      if (_processedEvents.contains(eventId) && eventName != 'force_ui_refresh') {
        print('Skipping duplicate event: $eventId');
        return;
      }

      // Add to processed events and schedule cleanup
      _processedEvents.add(eventId);
      Future.delayed(Duration(seconds: 5), () {
        _processedEvents.remove(eventId);
      });

      print('Processing ${eventName} event for game: $gameId');

      // Ensure data has action and timestamp
      if (!data.containsKey('action')) {
        data['action'] = eventName;
      }
      if (!data.containsKey('timestamp')) {
        data['timestamp'] = DateTime.now().toIso8601String();
      }

      // Process the event
      onUpdate(data);

      // Update last refresh time to prevent immediate periodic refresh
      lastRefreshTimes[gameId] = DateTime.now();
    }

    // Listen for all relevant events
    socketManager.on('game_update', gameEventHandler);
    socketManager.on('game_action_performed', gameEventHandler);
    socketManager.on('turn_changed', gameEventHandler);
    socketManager.on('game_started', gameEventHandler);
    socketManager.on('game_ended', gameEventHandler);
    socketManager.on('force_ui_refresh', gameEventHandler);

    // Handle refresh requests with higher priority and better logging
    socketManager.on('request_refresh', (data) {
      if (data['gameId'] == gameId && socketManager.authToken != null) {
        print('Received refresh request for game: $gameId');

        // Only refresh if we haven't recently
        final lastRefresh = lastRefreshTimes[gameId] ?? DateTime.now().subtract(Duration(seconds: 10));
        final timeSinceLastRefresh = DateTime.now().difference(lastRefresh);

        if (timeSinceLastRefresh.inSeconds > 1) {
          print('Executing refresh request - time since last refresh: ${timeSinceLastRefresh.inSeconds}s');
          // Get fresh state and broadcast
          gameService.getGame(gameId, socketManager.authToken!).then((result) {
            if (result['success']) {
              // Update last refresh time
              lastRefreshTimes[gameId] = DateTime.now();

              // Create update event with the fresh data
              final updateEvent = {
                'action': 'game_update',
                'gameId': gameId,
                'game': (result['game'] as GameModel).toJson(),
                'timestamp': DateTime.now().toIso8601String(),
                'source': 'refresh_request'
              };

              // Process locally
              onUpdate(updateEvent);

              // Broadcast to others
              socketManager.emit('game_action', updateEvent);

              print('State refresh completed for game: $gameId');
            } else {
              print('Failed to refresh state: ${result['message'] ?? 'Unknown error'}');
            }
          });
        } else {
          print('Skipping refresh request - too recent (${timeSinceLastRefresh.inSeconds}s)');
        }
      }
    });

    print('Enhanced game event listeners set up for: $gameId');
  }

  /// Helper method to emit events with more control
  static void emit(String event, dynamic data, SocketManager socketManager) {
    print('Emitting $event event with data: ${data.toString().substring(0, Math.min(100, data.toString().length))}...');

    if (!socketManager.isConnected) {
      print('Socket not connected, attempting to reconnect before emitting');

      // Force reconnection
      socketManager.forceReconnect();

      // Queue the emit for after connection with multiple retries
      for (int i = 0; i < 3; i++) {
        Future.delayed(Duration(milliseconds: 300 * (i + 1)), () {
          if (socketManager.isConnected) {
            print('Socket connected, emitting delayed event: $event (attempt ${i + 1})');
            socketManager.emit(event, data);
          }
        });
      }

      return;
    }

    // Send the event to socket manager
    socketManager.emit(event, data);

    // Add retries for important events
    if (event == 'game_action') {
      final action = data['action'];
      // For critical events, send multiple times
      if (action == 'turn_changed' ||
          action == 'game_action_performed' ||
          action == 'force_ui_refresh') {
        for (int i = 0; i < 2; i++) {
          Future.delayed(Duration(milliseconds: 150 * (i + 1)), () {
            if (socketManager.isConnected) {
              print('Sending retry ${i + 1} for critical event: $action');
              socketManager.emit(event, data);
            }
          });
        }
      }
    }
  }

  /// Force resynchronization of game state
  static Future<void> resyncGameState(String gameId, String authToken, SocketManager socketManager, dynamic gameService) async {
    print('Attempting to resync game state...');

    // Step 1: Force socket reconnection
    socketManager.forceReconnect();

    // Step 2: Explicit rejoin of the game room
    socketManager.joinGameRoom(gameId);

    // Step 3: Get latest game state from server
    await Future.delayed(Duration(milliseconds: 500));
    final result = await gameService.getGame(gameId, authToken);

    // Step 4: Broadcast a request for all clients to refresh
    if (result['success']) {
      // Increment state version
      _gameStateVersions[gameId] = (_gameStateVersions[gameId] ?? 0) + 1;

      // Create multiple events for redundancy
      final gameModel = result['game'] as GameModel;

      // Game update event
      socketManager.emit('game_action', {
        'gameId': gameId,
        'action': 'game_update',
        'game': gameModel.toJson(),
        'stateVersion': _gameStateVersions[gameId],
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'resync'
      });

      // Turn changed event
      socketManager.emit('game_action', {
        'gameId': gameId,
        'action': 'turn_changed',
        'currentPlayerIndex': gameModel.currentPlayerIndex,
        'game': gameModel.toJson(),
        'stateVersion': _gameStateVersions[gameId],
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'resync'
      });

      // Force UI refresh event
      socketManager.emit('game_action', {
        'gameId': gameId,
        'action': 'force_ui_refresh',
        'game': gameModel.toJson(),
        'stateVersion': _gameStateVersions[gameId],
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'resync'
      });

      // Request refresh event as backup
      socketManager.emit('game_action', {
        'gameId': gameId,
        'action': 'request_refresh',
        'timestamp': DateTime.now().toIso8601String()
      });

      print('Game state resynced successfully');
      return;
    }

    print('Failed to resync game state');
  }

  /// Check socket connection status
  static Future<Map<String, dynamic>> checkSocketStatus(String gameId, SocketManager socketManager) async {
    final socketId = socketManager.socketId;
    final isConnected = socketManager.isConnected;
    final joinedRooms = socketManager.joinedRooms;

    final status = {
      'success': true,
      'socketId': socketId,
      'isConnected': isConnected,
      'joinedRooms': joinedRooms.toList(),
      'isInRoom': joinedRooms.contains(gameId),
      'timestamp': DateTime.now().toIso8601String()
    };

    print('Socket status: $status');

    // Attempt to emit a status check event
    if (isConnected) {
      socketManager.emit('game_action', {
        'gameId': gameId,
        'action': 'status_check',
        'timestamp': DateTime.now().toIso8601String()
      });
    }

    return status;
  }

  /// Clear processed events cache
  static void clearCache() {
    _processedEvents.clear();
  }
}