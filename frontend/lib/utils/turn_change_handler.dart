import 'dart:async';
import 'package:flutter/material.dart';

/// Helper class to handle turn changes with special reliability
class TurnChangeHandler {
  /// Force a game state update on all clients when the turn changes
  static Future<void> forceTurnChangeUpdate(
      String gameId,
      String authToken,
      dynamic gameService,
      BuildContext context,
      Function updateUI) async {

    print('Forcing turn change update for game: $gameId');

    try {
      // 1. First get the fresh state from the server
      final result = await gameService.getGame(gameId, authToken);

      if (result['success']) {
        final game = result['game'];

        // 2. Send a special direct event to force UI updates
        for (int i = 0; i < 5; i++) {
          // Create a delay between attempts
          await Future.delayed(Duration(milliseconds: 200 * i));

          // Send turn_changed event specifically
          gameService.emit('game_action', {
            'gameId': gameId,
            'action': 'turn_changed',
            'previousPlayerIndex': game.currentPlayerIndex > 0 ? game.currentPlayerIndex - 1 : game.players.length - 1,
            'currentPlayerIndex': game.currentPlayerIndex,
            'game': game.toJson(),
            'timestamp': DateTime.now().toIso8601String(),
            'source': 'forced_turn_update',
            'retry': i
          });

          // Also send force_ui_refresh for immediate response
          gameService.emit('game_action', {
            'gameId': gameId,
            'action': 'force_ui_refresh',
            'game': game.toJson(),
            'timestamp': DateTime.now().toIso8601String(),
            'source': 'forced_turn_update',
            'retry': i
          });
        }

        // 3. Force UI update locally too
        updateUI();

        // 4. Show a confirmation of the sync
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Game state synced. Current player: ${game.players[game.currentPlayerIndex].username}'),
            duration: Duration(seconds: 2),
          ),
        );

        return;
      } else {
        // Show error if sync failed
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to sync game state: ${result['message']}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error forcing turn change update: $e');

      // Still try to update UI even on error
      updateUI();
    }
  }

  /// Special handler to be registered for listening to turn changes
  static void handleTurnChangedEvent(
      dynamic data,
      Function updateUI,
      Function showTurnNotification,
      Function(String) showActionSnackBar) {

    if (data == null) return;

    try {
      print('Processing turn change event: ${data['action']} (source: ${data['source'] ?? "unknown"})');

      // Update UI immediately regardless of other checks
      updateUI();

      // Extract player information if available
      String? playerName;
      bool isCurrentUserTurn = false;

      if (data['game'] != null && data['currentPlayerIndex'] != null) {
        final gameData = data['game'];
        final currentPlayerIndex = data['currentPlayerIndex'];

        if (gameData['players'] != null &&
            gameData['players'] is List &&
            currentPlayerIndex < gameData['players'].length) {

          final player = gameData['players'][currentPlayerIndex];
          playerName = player['username'];

          // Show action notification
          showActionSnackBar('It\'s $playerName\'s turn now');
        }
      }

      // Always update UI again after a delay to be sure
      Future.delayed(Duration(milliseconds: 300), () {
        updateUI();
      });
    } catch (e) {
      print('Error in turn change handler: $e');

      // Still try to update UI even on error
      updateUI();
    }
  }
}