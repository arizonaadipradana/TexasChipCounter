import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/game_model.dart';
import '../utils/socket_manager.dart';

/// API methods for game service
class GameServiceApi {
  /// Validate if a short game ID exists
  static Future<Map<String, dynamic>> validateGameId(String shortId,
      String authToken) async {
    try {
      print('Validating game ID with server: $shortId');

      // Call the server API directly with the short ID
      final response = await http.get(
        Uri.parse(
            '${ApiConfig.baseUrl}${ApiConfig.gamesEndpoint}/validate/$shortId'),
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

  /// Create a new game
  static Future<Map<String, dynamic>> createGame(String name,
      int smallBlind,
      int bigBlind,
      String authToken,) async {
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

  /// Helper method to extract user ID from token
  static Future<String?> _getUserIdFromToken(String token) async {
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

  /// Join a game with improved error handling
  static Future<Map<String, dynamic>> joinGame(String shortId, String authToken,
      SocketManager socketManager,
      Function(String, GameModel) notifyPlayerJoined) async {
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
          final isPlayerInGame =
          game.players.any((player) => player.userId == userId);
          if (isPlayerInGame) {
            print(
                'Player is already in this game, returning game object directly');

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
        Uri.parse(
            '${ApiConfig.baseUrl}${ApiConfig.gamesEndpoint}/$fullGameId/join'),
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
      } else if (response.statusCode == 200 &&
          responseData['alreadyJoined'] == true) {
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

  /// Get all games (for demo/testing)
  static Future<Map<String, dynamic>> getAllGames(String authToken) async {
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

  /// Get game details with improved error handling and throttling
  static Future<Map<String, dynamic>> getGame(String gameId,
      String authToken,) async {
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

        print(
            'Successfully fetched game details. Current player index: ${game
                .currentPlayerIndex}');

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

  /// Start a game
  static Future<Map<String, dynamic>> startGame(String gameId,
      String authToken,
      SocketManager socketManager,) async {
    try {
      final response = await http.put(
        Uri.parse(
            '${ApiConfig.baseUrl}${ApiConfig.gamesEndpoint}/$gameId/start'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final game = GameModel.fromJson(responseData['game']);

        // Notify all players that the game has started with broadcasting
        for (int i = 0; i < 3; i++) {
          // Send multiple times to ensure delivery
          Future.delayed(Duration(milliseconds: i * 300), () {
            socketManager.emit('game_action', {
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

  /// End a game
  static Future<Map<String, dynamic>> endGame(String gameId,
      String authToken,
      SocketManager socketManager,) async {
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
        for (int i = 0; i < 3; i++) {
          // Send multiple times to ensure delivery
          Future.delayed(Duration(milliseconds: i * 300), () {
            socketManager.emit('game_action', {
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

  /// Game action (check, call, raise, fold) with improved error handling
  static Future<Map<String, dynamic>> gameAction(String gameId,
      String actionType,
      String authToken,
      SocketManager socketManager,
      Map<String, DateTime> lastRefreshTimes,
      Function(String, String, int?, GameModel) broadcastActionWithRetries,
      {int? amount}) async {
    try {
      // Make sure we're in the game room
      if (!socketManager.isInRoom(gameId)) {
        socketManager.joinGameRoom(gameId);
        await Future.delayed(Duration(milliseconds: 300));
      }

      // Convert "bet" to "raise" for server
      String serverActionType = actionType;
      if (actionType == 'bet') {
        serverActionType = 'raise';
      }

      // Create request body
      final body = <String, dynamic>{
        'action': serverActionType,
      };
      if ((serverActionType == 'raise') && amount != null) {
        body['amount'] = amount;
      }

      print('Sending game action: $actionType to server for game: $gameId');

      // Send the action to the server
      final response = await http.post(
        Uri.parse(
            '${ApiConfig.baseUrl}${ApiConfig.gamesEndpoint}/$gameId/action'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final game = GameModel.fromJson(responseData['game']);

        // Update last refresh time
        lastRefreshTimes[gameId] = DateTime.now();

        // Aggressively broadcast the change with multiple events
        broadcastActionWithRetries(gameId, actionType, amount, game);

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

  /// Get active games
  static Future<Map<String, dynamic>> getActiveGames(String authToken) async {
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

  /// Get user's games
  static Future<Map<String, dynamic>> getUserGames(String authToken, {
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