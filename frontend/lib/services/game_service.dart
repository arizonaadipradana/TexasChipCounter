import 'dart:convert';
import 'dart:math' as Math;
import 'dart:async';  // Add Timer support
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/game_model.dart';
import '../utils/socket_manager.dart'; // Import the socket manager
import 'auth_service.dart';

class GameService {
  // Use the singleton socket manager instead of creating a socket directly
  final SocketManager _socketManager = SocketManager();

  // Throttle timers to prevent excessive API calls or emissions
  Timer? _actionThrottleTimer;
  Timer? _refreshThrottleTimer;
  Timer? _emitThrottleTimer;

  // Map to store game ID lookups (short ID to full ID)
  static final Map<String, String> _gameIdMap = {};

  // Initialize socket - now delegates to the socket manager
  void initSocket(String authToken, {String? userId}) {
    _socketManager.initSocket(authToken, userId: userId);
  }

  // Join a game room for real-time updates
  void joinGameRoom(String gameId) {
    print('Joining game room: $gameId');
    _socketManager.joinGameRoom(gameId);
  }

  // Leave a game room
  void leaveGameRoom(String gameId) {
    print('Leaving game room: $gameId');
    _socketManager.leaveGameRoom(gameId);
  }

  // Disconnect socket (only used when logging out or exiting the app)
  void disconnectSocket() {
    // This is now handled by the socket manager
    // We don't disconnect between screens anymore
  }

  void handlePlayerKick(String gameId) {
    // Leave the game room
    leaveGameRoom(gameId);

    // Clear game ID cache
    clearGameIdCache();

    // Log the event
    print('Handling player kick, game: $gameId');
  }

  // Listen for general game updates
  void listenForGameUpdates(Function(dynamic) onUpdate) {
    // Clear existing listeners to avoid duplicates
    _socketManager.clearListeners('game_update');
    _socketManager.clearListeners('game_action_performed');

    _socketManager.on('game_update', (data) {
      onUpdate(data);
    });

    _socketManager.on('game_action_performed', (data) {
      onUpdate(data);
    });
  }

  void listenForGameActions(Function(dynamic) onActionUpdate) {
    print('Setting up game action listeners');

    // Clear existing listeners to avoid duplicates
    _socketManager.clearListeners('game_action_performed');

    // Listen for actions that might change the pot
    _socketManager.on('game_action_performed', (data) {
      print('game_action_performed event received: $data');
      try {
        if (data != null) {
          onActionUpdate(data);
        }
      } catch (e) {
        print('Error processing game action event: $e');
      }
    });
  }

  // Listen for all game-related real-time updates with a single handler
  // This consolidates all event handlers to prevent socket disconnection issues
  // Update the listenForAllGameUpdates method to ensure all clients get updates
  void listenForAllGameUpdates(Function(dynamic) onUpdate) {
    print('Setting up consolidated game update listeners');

    // Clear existing listeners first to avoid duplicate handlers
    _clearAllGameEventListeners();

    // Create handler function that logs and passes to callback
    void gameEventHandler(dynamic data) {
      final eventName = data['action'] ?? 'game_update';
      print('Received $eventName event: ${data.toString().substring(0, Math.min(100, data.toString().length))}...');

      // Ensure the data includes proper action type for better handling
      if (!data.containsKey('action')) {
        data['action'] = eventName;
      }

      // Add timestamp if missing
      if (!data.containsKey('timestamp')) {
        data['timestamp'] = DateTime.now().toIso8601String();
      }

      // Process the event immediately
      onUpdate(data);

      // For critical game events, request a fresh state from the server
      if (eventName == 'turn_changed' ||
          eventName == 'game_action_performed' ||
          eventName == 'game_started') {

        // Request a state refresh after a short delay
        Future.delayed(Duration(milliseconds: 100), () {
          if (_socketManager.isConnected && data['gameId'] != null) {
            print('Requesting state refresh after $eventName event');
            // Create a new event to request a refresh of game state
            _socketManager.emit('game_action', {
              'action': 'request_refresh',
              'gameId': data['gameId'],
              'timestamp': DateTime.now().toIso8601String()
            });
          }
        });
      }
    }

    // Listen for all the different game events with the same handler
    _socketManager.on('game_update', gameEventHandler);
    _socketManager.on('game_action_performed', gameEventHandler);
    _socketManager.on('player_joined', gameEventHandler);
    _socketManager.on('player_left', gameEventHandler);
    _socketManager.on('player_kicked', gameEventHandler);
    _socketManager.on('game_started', gameEventHandler);
    _socketManager.on('game_ended', gameEventHandler);
    _socketManager.on('turn_changed', gameEventHandler);

    // Add a specific request_refresh handler
    _socketManager.on('request_refresh', (data) {
      print('Received refresh request, fetching latest game state...');

      if (data['gameId'] != null && _socketManager.authToken != null) {
        getGame(data['gameId'], _socketManager.authToken!)
            .then((result) {
          if (result['success']) {
            // Create a game_update event with the fresh data
            final updateEvent = {
              'action': 'game_update',
              'gameId': data['gameId'],
              'game': result['game'].toJson(),
              'timestamp': DateTime.now().toIso8601String(),
              'source': 'refresh_request'
            };

            // Pass through the update handler
            onUpdate(updateEvent);
          }
        });
      }
    });

    print('Consolidated game event listeners set up');
  }

  // IMPORTANT: This function clears all game-related event listeners
  // to avoid socket disconnection issues
  void _clearAllGameEventListeners() {
    // Clear listeners for all game-related events
    final gameEvents = [
      'game_update',
      'game_action_performed',
      'player_joined',
      'player_left',
      'player_kicked',
      'game_started',
      'game_ended',
      'turn_changed', // Also clear turn change listeners
    ];

    for (final event in gameEvents) {
      _socketManager.clearListeners(event);
    }

    print('Cleared all game event listeners');
  }

  void cleanupGameListeners() {
    _clearAllGameEventListeners();
  }

  // Helper method to handle game events consistently
  void _handleGameEvent(dynamic data, Function(GameModel) onUpdate, [Function(String, String)? onKicked]) {
    try {
      if (data != null && data['game'] != null) {
        final updatedGame = GameModel.fromJson(data['game']);

        // Call the update callback
        onUpdate(updatedGame);

        // If this is a kick event and the current user was kicked, call the kick callback
        if (onKicked != null &&
            data['action'] == 'player_kicked' &&
            data['kickedUserId'] == _socketManager.userId) {
          onKicked(updatedGame.id, data['removedBy'] ?? 'host');
        }
      }
    } catch (e) {
      print('Error processing event: $e');
    }
  }

  // Update the listenForPlayerUpdates method in GameService class
  void listenForPlayerUpdates(Function(GameModel) onPlayerUpdate, [Function(String, String)? onKicked]) {
    print('Setting up player update listeners with enhanced event handling');

    // Clear any existing listeners to avoid duplicates
    _socketManager.clearListeners('player_joined');
    _socketManager.clearListeners('player_left');
    _socketManager.clearListeners('player_kicked');
    _socketManager.clearListeners('game_started');
    _socketManager.clearListeners('game_update');

    // Listen for player join events
    _socketManager.on('player_joined', (data) {
      print('player_joined event received: $data');
      _handleGameEvent(data, onPlayerUpdate);
    });

    // Listen for player leave events
    _socketManager.on('player_left', (data) {
      print('player_left event received: $data');
      _handleGameEvent(data, onPlayerUpdate);
    });

    // Listen for player kick events
    _socketManager.on('player_kicked', (data) {
      print('player_kicked event received: $data');
      _handleGameEvent(data, onPlayerUpdate, onKicked);
    });

    // Listen for game started events - with higher priority
    _socketManager.on('game_started', (data) {
      print('game_started event received: $data');
      _handleGameEvent(data, onPlayerUpdate);
    });

    // Generic game update (fallback)
    _socketManager.on('game_update', (data) {
      print('game_update event received: $data');
      _handleGameEvent(data, onPlayerUpdate);
    });
  }

  // Register short game ID for lookup
  static void registerGameId(String fullId) {
    final shortId = fullId.substring(0, 6).toUpperCase();
    _gameIdMap[shortId] = fullId;
  }

  // Look up full game ID from short ID
  static String? getFullGameId(String shortId) {
    return _gameIdMap[shortId.toUpperCase()];
  }

  static void clearGameIdCache() {
    _gameIdMap.clear();
    print('Game ID cache cleared');
  }

  // Notify when a player joins
  void notifyPlayerJoined(String gameId, GameModel updatedGame) {
    print('Emitting player_joined event for game: $gameId');

    // Throttle to prevent rapid emissions
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

  // Notify when a player is removed (kicked by host)
  void notifyPlayerRemoved(String gameId, GameModel updatedGame, String removedUserId) {
    print('Emitting player_kicked event for game: $gameId');

    _socketManager.emit('game_action', {
      'gameId': gameId,
      'action': 'player_kicked',
      'kickedUserId': removedUserId,
      'game': updatedGame.toJson(),
      'timestamp': DateTime.now().toIso8601String(),
      'removedBy': _socketManager.userId
    });

    print('Kick notification emitted for player: $removedUserId');
  }

  // Add this method to your GameService class
  void emit(String event, dynamic data) {
    print('Emitting $event event with data: ${data.toString().substring(0, Math.min(100, data.toString().length))}...');

    if (!_socketManager.isConnected) {
      print('Socket not connected, attempting to reconnect before emitting');

      // Force reconnection
      _socketManager.forceReconnect();

      // Queue the emit for after connection with multiple retries
      for (int i = 0; i < 3; i++) {
        Future.delayed(Duration(milliseconds: 300 * (i + 1)), () {
          if (_socketManager.isConnected) {
            print('Socket connected, emitting delayed event: $event (attempt ${i+1})');
            _socketManager.emit(event, data);
          }
        });
      }

      return;
    }

    // Send the event to socket manager
    _socketManager.emit(event, data);

    // Add retries for important events
    if (event == 'game_action') {
      for (int i = 0; i < 2; i++) {
        Future.delayed(Duration(milliseconds: 150 * (i + 1)), () {
          if (_socketManager.isConnected) {
            print('Sending retry ${i+1} for event: $event');
            _socketManager.emit(event, data);
          }
        });
      }
    }
  }

  // Notify when a player is quitting voluntarily
  void notifyPlayerQuitting(String gameId, GameModel updatedGame) {
    print('Emitting player_left event for game: $gameId');

    _socketManager.emit('game_action', {
      'gameId': gameId,
      'action': 'player_left',
      'userId': _socketManager.userId,
      'game': updatedGame.toJson(),
      'timestamp': DateTime.now().toIso8601String()
    });

    print('Player left notification emitted');
  }

  // Validate if a short game ID exists
  Future<Map<String, dynamic>> validateGameId(String shortId, String authToken) async {
    try {
      print('Validating game ID with server: $shortId');

      // Call the server API directly with the short ID
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.gamesEndpoint}/validate/$shortId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );

      print('Validation response status: ${response.statusCode}');
      print('Validation response body: ${response.body}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success']) {
        return {
          'success': true,
          'gameId': responseData['gameId'],
          'exists': responseData['exists'],
        };
      }

      print('Failed to validate game ID: ${responseData['message']}');
      return {
        'success': false,
        'message': responseData['message'] ?? 'Game not found',
        'exists': false,
      };
    } catch (e) {
      print('Error validating game ID: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
        'exists': false,
      };
    }
  }

  // Create a new game
  Future<Map<String, dynamic>> createGame(
      String name,
      int smallBlind,
      int bigBlind,
      String authToken,
      ) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.gamesEndpoint}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'name': name,
          'smallBlind': smallBlind,
          'bigBlind': bigBlind,
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 201) {
        final game = GameModel.fromJson(responseData['game']);

        // Get the shortId from the response and set it on the game object
        final shortId = responseData['shortId'];
        if (shortId != null && shortId is String) {
          // Update the game's shortId property directly
          game.shortId = shortId;
        }

        return {
          'success': true,
          'game': game,
          'shortId': shortId,
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to create game',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  Future<String?> _getUserIdFromToken(String token) async {
    try {
      // Make a request to the user info endpoint
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/users/me'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['user']['_id'];
      }
    } catch (e) {
      print('Error getting user ID from token: $e');
    }
    return null;
  }

  // Join a game with improved error handling
  Future<Map<String, dynamic>> joinGame(String shortId, String authToken) async {
    try {
      print('Attempting to join game with ID: $shortId');

      // First validate if the game exists
      final validation = await validateGameId(shortId, authToken);
      print('Game validation result: $validation');

      if (!validation['exists']) {
        print('Game does not exist according to validation');
        return {
          'success': false,
          'message': 'Invalid Game ID. Please check and try again.',
        };
      }

      final fullGameId = validation['gameId'];
      if (fullGameId == null) {
        return {
          'success': false,
          'message': 'Could not resolve full game ID',
        };
      }

      print('Full game ID for joining: $fullGameId');

      // First get the game details to check if player is already in the game
      final gameDetails = await getGame(fullGameId, authToken);
      if (gameDetails['success']) {
        // Check if the player is already in this game
        final game = gameDetails['game'] as GameModel;
        final userId = await _getUserIdFromToken(authToken);

        if (userId != null) {
          final isPlayerInGame = game.players.any((player) => player.userId == userId);
          if (isPlayerInGame) {
            print('Player is already in this game, returning game object directly');

            // Set the short ID on the game model
            game.shortId = shortId;

            // Even if already joined, notify everyone to ensure state is synchronized
            notifyPlayerJoined(fullGameId, game);

            return {
              'success': true,
              'game': game,
              'alreadyJoined': true,
            };
          }
        }
      }

      // Player not in the game yet, proceed with join request
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.gamesEndpoint}/$fullGameId/join'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );

      print('Join game response status: ${response.statusCode}');
      print('Join game response body: ${response.body}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('Successfully joined game');
        final game = GameModel.fromJson(responseData['game']);

        // Make sure shortId is set on the model
        if (game.shortId == null || game.shortId!.isEmpty) {
          game.shortId = shortId;
        }

        // Notify all players about the new player
        notifyPlayerJoined(fullGameId, game);

        return {
          'success': true,
          'game': game,
        };
      } else if (response.statusCode == 200 && responseData['alreadyJoined'] == true) {
        // Handle the "already in game" case
        print('Player is already in this game according to server');
        final game = GameModel.fromJson(responseData['game']);

        // Make sure shortId is set on the model
        if (game.shortId == null || game.shortId!.isEmpty) {
          game.shortId = shortId;
        }

        // Notify everyone even on rejoin to refresh the player list
        notifyPlayerJoined(fullGameId, game);

        return {
          'success': true,
          'game': game,
          'alreadyJoined': true,
        };
      } else {
        print('Failed to join game: ${responseData['message']}');
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to join game',
        };
      }
    } catch (e) {
      print('Error joining game: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Get all games (for demo/testing)
  Future<Map<String, dynamic>> getAllGames(String authToken) async {
    try {
      // Change the endpoint from /api/games/all to /api/games?status=all
      // This avoids the backend treating "all" as an ID
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.gamesEndpoint}?status=all'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        List<GameModel> games = (responseData['games'] as List)
            .map((game) => GameModel.fromJson(game))
            .toList();

        // Register all game IDs for local lookup
        for (var game in games) {
          registerGameId(game.id);
        }

        return {
          'success': true,
          'games': games,
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to get games',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Get game details with improved error handling and throttling
  Future<Map<String, dynamic>> getGame(
      String gameId,
      String authToken,
      ) async {
    // If a refresh is already in progress, cancel it to avoid multiple calls
    if (_refreshThrottleTimer != null && _refreshThrottleTimer!.isActive) {
      return {
        'success': false,
        'message': 'Refresh already in progress',
      };
    }

    // Set throttle timer to prevent excessive API calls
    _refreshThrottleTimer = Timer(Duration(milliseconds: 500), () {});

    try {
      print('Fetching game details for ID: $gameId');

      // Check if it's a short ID (6 characters) needing conversion
      String fullGameId = gameId;
      if (gameId.length == 6) {
        final validation = await validateGameId(gameId, authToken);
        if (!validation['exists']) {
          return {
            'success': false,
            'message': 'Game not found',
          };
        }
        fullGameId = validation['gameId'];
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.gamesEndpoint}/$fullGameId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );

      print('Game details response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final game = GameModel.fromJson(responseData['game']);

        // If the original gameId was a short ID, set it on the model
        if (gameId.length == 6) {
          game.shortId = gameId.toUpperCase();
        }

        // Also set the shortId from the response if available
        if (responseData['game']['shortId'] != null) {
          game.shortId = responseData['game']['shortId'];
        }

        print('Successfully fetched game details. Current player index: ${game.currentPlayerIndex}');

        return {
          'success': true,
          'game': game,
        };
      } else {
        var message = 'Failed to get game details';
        try {
          final responseData = jsonDecode(response.body);
          message = responseData['message'] ?? message;
        } catch (e) {
          // If the response isn't valid JSON, just use the default message
        }

        return {
          'success': false,
          'message': message,
        };
      }
    } catch (e) {
      print('Error fetching game details: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Start a game
  Future<Map<String, dynamic>> startGame(
      String gameId,
      String authToken,
      ) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.gamesEndpoint}/$gameId/start'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final game = GameModel.fromJson(responseData['game']);

        // Notify all players that the game has started with broadcasting
        for (int i = 0; i < 3; i++) { // Send multiple times to ensure delivery
          Future.delayed(Duration(milliseconds: i * 300), () {
            _socketManager.emit('game_action', {
              'gameId': gameId,
              'action': 'game_started',
              'game': game.toJson(),
              'timestamp': DateTime.now().toIso8601String()
            });
          });
        }

        return {
          'success': true,
          'game': game,
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to start game',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // End a game
  Future<Map<String, dynamic>> endGame(
      String gameId,
      String authToken,
      ) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.gamesEndpoint}/$gameId/end'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final game = GameModel.fromJson(responseData['game']);

        // Notify all players that the game has ended with retry mechanism
        for (int i = 0; i < 3; i++) { // Send multiple times to ensure delivery
          Future.delayed(Duration(milliseconds: i * 300), () {
            _socketManager.emit('game_action', {
              'gameId': gameId,
              'action': 'game_ended',
              'game': game.toJson(),
              'timestamp': DateTime.now().toIso8601String()
            });
          });
        }

        return {
          'success': true,
          'game': game,
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to end game',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Game action (check, call, raise, fold) with improved error handling
  Future<Map<String, dynamic>> gameAction(
      String gameId,
      String actionType,
      String authToken,
      {int? amount}
      ) async {
    try {
      // Make sure we're in the game room
      if (!_socketManager.isInRoom(gameId)) {
        _socketManager.joinGameRoom(gameId);
        await Future.delayed(Duration(milliseconds: 300));
      }

      // Convert "bet" to "raise" since the server seems to use "raise" for both
      String serverActionType = actionType;
      if (actionType == 'bet') {
        serverActionType = 'raise';  // Use "raise" for the first bet in a round
      }

      // Create the request body
      final body = <String, dynamic>{
        'action': serverActionType,  // Use the converted action type
      };

      // For raise actions, amount is required
      if ((serverActionType == 'raise') && amount != null) {
        body['amount'] = amount;
      }

      print('Sending game action: $actionType (as $serverActionType) to server for game: $gameId');
      print('Request body: $body');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.gamesEndpoint}/$gameId/action'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode(body),
      );

      print('Game action response status: ${response.statusCode}');
      print('Game action response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final game = GameModel.fromJson(responseData['game']);

        // Improved broadcasting with multiple events for redundancy
        _broadcastActionWithRedundancy(gameId, actionType, amount, game);

        return {
          'success': true,
          'message': responseData['message'] ?? 'Action performed successfully',
          'game': game,
        };
      } else {
        final responseData = jsonDecode(response.body);
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to perform action',
        };
      }
    } catch (e) {
      print('Error in gameAction: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  // New method for redundant broadcasting to ensure all clients get the update
  void _broadcastActionWithRedundancy(String gameId, String action, int? amount, GameModel game) {
    // Emit multiple events with different delays to make sure clients receive the update

    // 1. Emit turn_changed event immediately
    _socketManager.emit('game_action', {
      'gameId': gameId,
      'action': 'turn_changed',
      'previousPlayerIndex': game.currentPlayerIndex > 0 ? game.currentPlayerIndex - 1 : game.players.length - 1,
      'currentPlayerIndex': game.currentPlayerIndex,
      'game': game.toJson(),
      'timestamp': DateTime.now().toIso8601String()
    });

    // 2. Emit game_action_performed with details (100ms delay)
    Future.delayed(Duration(milliseconds: 100), () {
      _socketManager.emit('game_action', {
        'gameId': gameId,
        'action': 'game_action_performed',
        'actionType': action,
        'amount': amount,
        'previousPlayerIndex': game.currentPlayerIndex > 0 ? game.currentPlayerIndex - 1 : game.players.length - 1,
        'currentPlayerIndex': game.currentPlayerIndex,
        'game': game.toJson(),
        'timestamp': DateTime.now().toIso8601String()
      });
    });

    // 3. Emit general game_update (200ms delay)
    Future.delayed(Duration(milliseconds: 200), () {
      _socketManager.emit('game_action', {
        'gameId': gameId,
        'action': 'game_update',
        'game': game.toJson(),
        'timestamp': DateTime.now().toIso8601String()
      });
    });

    // 4. Request refresh from all clients (300ms delay)
    Future.delayed(Duration(milliseconds: 300), () {
      _socketManager.emit('game_action', {
        'gameId': gameId,
        'action': 'request_refresh',
        'timestamp': DateTime.now().toIso8601String()
      });
    });

    // 5. One more game_update for redundancy (500ms delay)
    Future.delayed(Duration(milliseconds: 500), () {
      _socketManager.emit('game_action', {
        'gameId': gameId,
        'action': 'game_update',
        'game': game.toJson(),
        'timestamp': DateTime.now().toIso8601String()
      });
    });
  }

  // Helper method to broadcast action to all players with retry mechanism
  void _broadcastActionToPlayers(String gameId, String action, int? amount, GameModel game) {
    // Emit multiple events to ensure all clients receive the update

    // First, emit a turn change event to update the UI immediately
    _socketManager.emit('game_action', {
      'gameId': gameId,
      'action': 'turn_changed',
      'previousPlayerIndex': game.currentPlayerIndex > 0 ? game.currentPlayerIndex - 1 : game.players.length - 1,
      'currentPlayerIndex': game.currentPlayerIndex,
      'game': game.toJson(),
      'timestamp': DateTime.now().toIso8601String()
    });

    // Then emit a game action event with full details
    Future.delayed(Duration(milliseconds: 100), () {
      _socketManager.emit('game_action', {
        'gameId': gameId,
        'action': 'game_action_performed',
        'actionType': action,
        'amount': amount,
        'game': game.toJson(),
        'timestamp': DateTime.now().toIso8601String()
      });
    });

    // Send a general game update as backup
    Future.delayed(Duration(milliseconds: 200), () {
      _socketManager.emit('game_action', {
        'gameId': gameId,
        'action': 'game_update',
        'game': game.toJson(),
        'timestamp': DateTime.now().toIso8601String()
      });
    });
  }

  // Get active games
  Future<Map<String, dynamic>> getActiveGames(String authToken) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.gamesEndpoint}/active'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        List<GameModel> games = (responseData['games'] as List)
            .map((game) => GameModel.fromJson(game))
            .toList();

        return {
          'success': true,
          'games': games,
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to get active games',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Get user's games
  Future<Map<String, dynamic>> getUserGames(
      String authToken, {
        String? status,
      }) async {
    try {
      String url = '${ApiConfig.baseUrl}${ApiConfig.gamesEndpoint}/my-games';
      if (status != null) {
        url += '?status=$status';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        List<GameModel> games = (responseData['games'] as List)
            .map((game) => GameModel.fromJson(game))
            .toList();

        return {
          'success': true,
          'games': games,
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to get user games',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> debugGameAction(
      String gameId,
      String action,
      String authToken,
      {int? amount}
      ) async {
    try {
      // Create a fully detailed request body
      final body = <String, dynamic>{
        'action': action,
      };

      // For bet and raise actions, must include the amount
      if (action == 'bet' || action == 'raise') {
        body['amount'] = amount;
      }

      print('DEBUG - Sending action to server:');
      print('Endpoint: ${ApiConfig.baseUrl}${ApiConfig.gamesEndpoint}/$gameId/action');
      print('Headers: Bearer Token (redacted)');
      print('Body: $body');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.gamesEndpoint}/$gameId/action'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode(body),
      );

      print('DEBUG - Full response:');
      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');

      return {
        'success': response.statusCode >= 200 && response.statusCode < 300,
        'status': response.statusCode,
        'body': response.body,
        'message': 'Debug completed'
      };
    } catch (e) {
      print('DEBUG - Error: $e');
      return {
        'success': false,
        'message': 'Error: $e',
      };
    }
  }

  Future<void> resyncGameState(String gameId, String authToken) async {
    print('Attempting to resync game state...');

    // Step 1: Force socket reconnection
    _socketManager.forceReconnect();

    // Step 2: Explicit rejoin of the game room
    _socketManager.joinGameRoom(gameId);

    // Step 3: Get latest game state from server
    await Future.delayed(Duration(milliseconds: 500));
    final result = await getGame(gameId, authToken);

    // Step 4: Broadcast a request for all clients to refresh
    if (result['success']) {
      _socketManager.emit('game_action', {
        'gameId': gameId,
        'action': 'request_refresh',
        'timestamp': DateTime.now().toIso8601String()
      });

      print('Game state resynced successfully');
      return;
    }

    print('Failed to resync game state');
  }

  Future<Map<String, dynamic>> checkSocketStatus(String gameId) async {
    final socketId = _socketManager.socketId;
    final isConnected = _socketManager.isConnected;
    final joinedRooms = _socketManager.joinedRooms;

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
      _socketManager.emit('game_action', {
        'gameId': gameId,
        'action': 'status_check',
        'timestamp': DateTime.now().toIso8601String()
      });
    }

    return status;
  }

}