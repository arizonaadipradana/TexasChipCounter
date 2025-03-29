import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/game_model.dart';
import '../utils/socket_manager.dart'; // Import the socket manager
import 'auth_service.dart';

class GameService {
  // Use the singleton socket manager instead of creating a socket directly
  final SocketManager _socketManager = SocketManager();

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

  // Listen specifically for player join/leave events
  void listenForPlayerUpdates(Function(GameModel) onPlayerUpdate, [Function(String, String)? onKicked]) {
    print('Setting up player update listeners');

    // Clear any existing listeners to avoid duplicates
    _socketManager.clearListeners('player_joined');
    _socketManager.clearListeners('player_left');
    _socketManager.clearListeners('player_kicked');
    _socketManager.clearListeners('game_started');
    _socketManager.clearListeners('game_update');

    // Listen for player join events
    _socketManager.on('player_joined', (data) {
      print('player_joined event received: $data');
      try {
        if (data != null && data['game'] != null) {
          final updatedGame = GameModel.fromJson(data['game']);
          onPlayerUpdate(updatedGame);
        }
      } catch (e) {
        print('Error processing player_joined event: $e');
      }
    });

    // Listen for player leave events
    _socketManager.on('player_left', (data) {
      print('player_left event received: $data');
      try {
        if (data != null && data['game'] != null) {
          final updatedGame = GameModel.fromJson(data['game']);
          onPlayerUpdate(updatedGame);
        }
      } catch (e) {
        print('Error processing player_left event: $e');
      }
    });

    // Listen for player kick events
    _socketManager.on('player_kicked', (data) {
      print('player_kicked event received: $data');
      try {
        if (data != null && data['game'] != null) {
          final updatedGame = GameModel.fromJson(data['game']);

          // Update the game for all players
          onPlayerUpdate(updatedGame);

          // If current user was kicked, trigger the callback
          if (onKicked != null && data['kickedUserId'] == _socketManager.userId) {
            onKicked(updatedGame.id, data['removedBy'] ?? 'host');
          }
        }
      } catch (e) {
        print('Error processing player_kicked event: $e');
      }
    });

    // Listen for game started events
    _socketManager.on('game_started', (data) {
      print('game_started event received: $data');
      try {
        if (data != null && data['game'] != null) {
          final updatedGame = GameModel.fromJson(data['game']);
          onPlayerUpdate(updatedGame);
        }
      } catch (e) {
        print('Error processing game_started event: $e');
      }
    });

    // Generic game update (fallback)
    _socketManager.on('game_update', (data) {
      print('game_update event received: $data');
      try {
        if (data != null && data['game'] != null) {
          final updatedGame = GameModel.fromJson(data['game']);
          onPlayerUpdate(updatedGame);
        }
      } catch (e) {
        print('Error processing game_update event: $e');
      }
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

  // Notify when a player joins
  void notifyPlayerJoined(String gameId, GameModel updatedGame) {
    print('Emitting player_joined event for game: $gameId');
    _socketManager.emit('game_action', {
      'gameId': gameId,
      'action': 'player_joined',
      'game': updatedGame.toJson(),
      'timestamp': DateTime.now().toIso8601String()
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
      // First check local map for faster response
      final fullId = getFullGameId(shortId);
      if (fullId != null) {
        print('Found game ID in local cache: $fullId for short ID: $shortId');
        return {
          'success': true,
          'gameId': fullId,
          'exists': true,
        };
      }

      print('Validating game ID with server: $shortId');

      // If not in local map, check with server
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
        // Save the mapping for future reference if it exists
        if (responseData['exists'] && responseData['gameId'] != null) {
          _gameIdMap[shortId.toUpperCase()] = responseData['gameId'];
          print('Saved game ID mapping: ${shortId.toUpperCase()} -> ${responseData['gameId']}');
        } else {
          print('Game with ID $shortId does not exist on the server');
        }

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

        // Register the game ID for local lookup
        registerGameId(game.id);

        return {
          'success': true,
          'game': game,
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

  // Join a game
  Future<Map<String, dynamic>> joinGame(String gameId, String authToken) async {
    try {
      print('Attempting to join game with ID: $gameId');

      // First validate if the game exists
      final validation = await validateGameId(gameId, authToken);
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

        // Notify all players about the new player
        notifyPlayerJoined(fullGameId, game);

        return {
          'success': true,
          'game': game,
        };
      } else if (response.statusCode == 400 &&
          responseData['message']?.contains('already in this game') == true) {
        // Handle the "already in game" case
        print('Player is already in this game according to server');

        // Get the game details again to get the latest state
        final latestGame = await getGame(fullGameId, authToken);
        if (latestGame['success']) {
          // Notify everyone even on rejoin to refresh the player list
          final game = latestGame['game'] as GameModel;
          notifyPlayerJoined(fullGameId, game);

          return {
            'success': true,
            'game': game,
            'alreadyJoined': true,
          };
        } else {
          return latestGame; // Return the error from getGame
        }
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

  // Get game details
  Future<Map<String, dynamic>> getGame(
      String gameId,
      String authToken,
      ) async {
    try {
      // Check if it's a short ID needing conversion
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

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'game': GameModel.fromJson(responseData['game']),
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to get game details',
        };
      }
    } catch (e) {
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

        // Notify all players that the game has started
        _socketManager.emit('game_action', {
          'gameId': gameId,
          'action': 'game_started',
          'game': game.toJson(),
          'timestamp': DateTime.now().toIso8601String()
        });

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

        // Notify all players that the game has ended
        _socketManager.emit('game_action', {
          'gameId': gameId,
          'action': 'game_ended',
          'game': game.toJson(),
          'timestamp': DateTime.now().toIso8601String()
        });

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

  // Game action (check, call, raise, fold)
  Future<Map<String, dynamic>> gameAction(
      String gameId,
      String action,
      String authToken,
      {int? amount}
      ) async {
    try {
      final body = <String, dynamic>{
        'action': action,
      };

      if (amount != null) {
        body['amount'] = amount;
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.gamesEndpoint}/$gameId/action'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode(body),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final game = GameModel.fromJson(responseData['game']);

        // Notify all players about the action
        _socketManager.emit('game_action', {
          'gameId': gameId,
          'action': 'game_action_performed',
          'actionType': action,
          'amount': amount,
          'game': game.toJson(),
          'timestamp': DateTime.now().toIso8601String()
        });

        return {
          'success': true,
          'message': responseData['message'],
          'game': game,
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to perform action',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
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
}