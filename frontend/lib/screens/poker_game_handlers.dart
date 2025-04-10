import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game_model.dart';
import '../models/poker_game_model.dart';
import '../models/user_model.dart';
import '../services/game_service_core.dart';
import '../utils/turn_change_handler.dart';
import 'poker_game_state.dart';
import 'home_screen.dart';

/// Handles game events and user actions
class PokerGameHandlers {
  final Function updateUI;
  final Function(String, Color) showTurnChangeNotification;
  final Function(String) showActionSnackBar;
  final Function(bool) setHandStarted;

  // Add a debouncer to prevent excessive UI updates
  Timer? _debounceTimer;
  DateTime? _lastUpdateTime;
  Set<String> _processedEventIds = {};

  PokerGameHandlers({
    required this.updateUI,
    required this.showTurnChangeNotification,
    required this.showActionSnackBar,
    required this.setHandStarted,
  });

  /// Handle app lifecycle changes
  void handleAppLifecycleChange(
      AppLifecycleState state,
      GameService? gameService,
      String gameId,
      bool isExiting,
      BuildContext context) {
    // When app comes back to foreground, force refresh
    if (state == AppLifecycleState.resumed) {
      print('App resumed, forcing game state refresh');

      if (gameService != null && !isExiting) {
        final userModel = Provider.of<UserModel>(context, listen: false);
        if (userModel.authToken != null) {
          forceStateRefresh(gameService, gameId, userModel.authToken!);
        }
      }
    }
  }

  /// Force a state refresh from the server
  void forceStateRefresh(GameService gameService, String gameId, String authToken) {
    gameService.forceStateSynchronization(gameId, authToken);

    // Update UI immediately
    updateUI();
  }

  /// Handle game updates from socket/real-time events with improved debouncing
  void handleGameUpdate(dynamic data, PokerGameModel pokerGame, BuildContext context) {
    if (data == null) return;

    try {
      final eventType = data['action'] ?? 'unknown';
      final timestamp = data['timestamp'] ?? DateTime.now().toIso8601String();

      // Create a unique event ID to prevent duplicate processing
      final eventId = '${eventType}_${timestamp}';

      // Skip if we've already processed this exact event
      if (_processedEventIds.contains(eventId)) {
        print('Skipping duplicate event: $eventId');
        return;
      }

      // Add to processed set and limit its size
      _processedEventIds.add(eventId);
      if (_processedEventIds.length > 100) {
        _processedEventIds = _processedEventIds.skip(_processedEventIds.length - 50).toSet();
      }

      print('Processing game event: $eventType (ID: $eventId)');

      // Check if it's too soon to update UI again
      final now = DateTime.now();
      final shouldDebounce = _lastUpdateTime != null &&
          now.difference(_lastUpdateTime!).inMilliseconds < 200;

      // If game data is available, update our model
      if (data['game'] != null) {
        final updatedGame = GameModel.fromJson(data['game']);

        // Track if player index changed
        final oldPlayerIndex = pokerGame.gameModel.currentPlayerIndex;
        final newPlayerIndex = updatedGame.currentPlayerIndex;
        bool playerIndexChanged = oldPlayerIndex != newPlayerIndex;

        // Update base game properties
        pokerGame.gameModel.status = updatedGame.status;
        pokerGame.gameModel.currentPlayerIndex = updatedGame.currentPlayerIndex;
        pokerGame.gameModel.pot = updatedGame.pot ?? pokerGame.gameModel.pot;
        pokerGame.gameModel.currentBet = updatedGame.currentBet ?? pokerGame.gameModel.currentBet;

        // Update player data more aggressively
        if (updatedGame.players.isNotEmpty) {
          // Update players from the fresh data
          for (int i = 0; i < pokerGame.players.length && i < updatedGame.players.length; i++) {
            final updatedPlayer = updatedGame.players[i];

            // Update important player properties
            pokerGame.players[i].chipBalance = updatedPlayer.chipBalance;

            // Handle action-specific updates
            if (data['action'] == 'game_action_performed' &&
                data['actionType'] != null &&
                data['previousPlayerIndex'] != null &&
                data['previousPlayerIndex'] == i) {

              switch(data['actionType']) {
                case 'bet':
                case 'raise':
                  if (data['amount'] != null) {
                    pokerGame.players[i].currentBet =
                    (data['amount'] is int) ? data['amount'] : int.parse(data['amount'].toString());
                  }
                  break;
                case 'call':
                  pokerGame.players[i].currentBet = pokerGame.gameModel.currentBet ?? 0;
                  break;
                case 'fold':
                  pokerGame.players[i].hasFolded = true;
                  break;
              }
            }
          }
        }

        // Start hand if needed
        if (updatedGame.status == GameStatus.active && !pokerGame.handInProgress) {
          pokerGame.handInProgress = true;
          setHandStarted(true);
        }

        // Cancel any pending debounce timer
        _debounceTimer?.cancel();

        // Special case for force_ui_refresh - always update immediately
        if (eventType == 'force_ui_refresh') {
          updateUI();
          _lastUpdateTime = now;
          return;
        }

        // For turn changes, show notification immediately
        if (playerIndexChanged) {
          // Update UI immediately for turn changes
          updateUI();
          _lastUpdateTime = now;

          // Show turn change notification
          if (newPlayerIndex < pokerGame.players.length) {
            final playerName = pokerGame.players[newPlayerIndex].username;
            final isCurrentUserTurn = pokerGame.players[newPlayerIndex].userId ==
                Provider.of<UserModel>(context, listen: false).id;

            showTurnChangeNotification(
                isCurrentUserTurn ? 'Your turn!' : 'It\'s $playerName\'s turn',
                isCurrentUserTurn ? Colors.green : Colors.blue
            );
          }
        } else if (shouldDebounce) {
          // Debounce other updates to avoid UI flickering
          _debounceTimer = Timer(Duration(milliseconds: 200), () {
            updateUI();
            _lastUpdateTime = DateTime.now();
          });
        } else {
          // Update UI if not debouncing
          updateUI();
          _lastUpdateTime = now;
        }
      }

      // Handle game action
      if (data['action'] == 'game_action_performed' && data['actionType'] != null) {
        _handleGameAction(data, pokerGame);
      }

      // Check if game is complete
      if (data['action'] == 'game_ended' ||
          (data['game'] != null && GameModel.fromJson(data['game']).status == GameStatus.completed)) {
        // If game ended, navigate back to home
        _handleGameEnded(context);
      }
    } catch (e) {
      print('Error handling game update: $e');

      // Still update UI even if there was an error
      updateUI();
    }
  }

  /// Handle game action update
  void _handleGameAction(dynamic data, PokerGameModel pokerGame) {
    try {
      final actionType = data['actionType'];
      final amount = data['amount'];
      final playerIndex = data['previousPlayerIndex'] ??
          (pokerGame.currentPlayerIndex > 0 ?
          pokerGame.currentPlayerIndex - 1 :
          pokerGame.players.length - 1);

      if (playerIndex >= 0 && playerIndex < pokerGame.players.length) {
        final player = pokerGame.players[playerIndex];

        // Update player state based on action type
        switch (actionType) {
          case 'fold':
            player.hasFolded = true;
            player.hasActed = true;
            break;
          case 'check':
            player.hasActed = true;
            break;
          case 'bet':
          case 'raise':
            if (amount != null) {
              // Convert to int first
              final amountInt = amount is int ? amount : int.parse(amount.toString());
              player.currentBet = amountInt;
              player.hasActed = true;

              // Update pot and current bet
              pokerGame.pot += amountInt;
              pokerGame.gameModel.pot = pokerGame.pot;
              pokerGame.gameModel.currentBet = amountInt;
            }
            break;
          case 'call':
            final callAmount = data['amount'] ?? pokerGame.gameModel.currentBet;
            // Convert to int first
            final callAmountInt = callAmount is int ? callAmount : int.parse(callAmount.toString());
            player.currentBet = callAmountInt;
            player.hasActed = true;

            // Update pot
            pokerGame.pot += callAmountInt;
            pokerGame.gameModel.pot = pokerGame.pot;
            break;
        }

        // Force table update
        updateUI();

        // Display action notification
        String actionMessage = '${player.username} ';
        if (actionType == 'fold') {
          actionMessage += 'folded';
        } else if (actionType == 'check') {
          actionMessage += 'checked';
        } else if (actionType == 'call') {
          actionMessage += 'called ${pokerGame.gameModel.currentBet} chips';
        } else if (actionType == 'bet') {
          actionMessage += 'bet $amount chips';
        } else if (actionType == 'raise') {
          actionMessage += 'raised to $amount chips';
        }

        showActionSnackBar(actionMessage);
      }
    } catch (e) {
      print('Error handling game action: $e');

      // Still update UI even if there was an error
      updateUI();
    }
  }

  /// Handle game ended event
  void _handleGameEnded(BuildContext context) {
    // Navigate back to home screen
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  /// Handle player action (fold, check, call, raise)
  Future<void> handleAction(String action, PokerGameModel pokerGame,
      UserModel userModel, GameService? gameService, String gameId,
      BuildContext context, {int? amount}) async {
    if (gameService == null || userModel.authToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Service not initialized'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // Show "Processing..." indicator
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
              ),
              SizedBox(width: 8),
              Text('Processing $action...'),
            ],
          ),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Pre-update local model to make UI more responsive
      _preUpdateLocalModel(action, amount, pokerGame);

      // Update UI immediately for responsiveness
      updateUI();

      // Call the server API
      final result = await gameService.gameAction(
        gameId,
        action,
        userModel.authToken!,
        amount: amount,
      );

      if (result['success']) {
        // Get the updated game model
        final updatedGame = result['game'] as GameModel;

        // Update model
        pokerGame.gameModel.currentPlayerIndex = updatedGame.currentPlayerIndex;
        pokerGame.gameModel.pot = updatedGame.pot ?? pokerGame.gameModel.pot;
        pokerGame.gameModel.currentBet = updatedGame.currentBet ?? pokerGame.gameModel.currentBet;

        // Record the action locally
        pokerGame.performAction(action, amount: amount);

        // Update UI
        updateUI();

        // Show confirmation message
        _showActionConfirmationMessage(action, amount, pokerGame);
      } else {
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Action failed'),
            backgroundColor: Colors.red,
          ),
        );

        // Force a state refresh to ensure consistency
        forceStateRefresh(gameService, gameId, userModel.authToken!);
      }
    } catch (e) {
      // Handle API errors
      String errorMessage = 'Network error occurred';

      // Extract specific error message if possible
      if (e.toString().contains('Bet amount must be at least the big blind')) {
        errorMessage = 'Bet amount must be at least the big blind';
      } else if (e.toString().contains('Raise must be at least')) {
        errorMessage = 'Raise amount is too small';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );

      // Force UI update and state refresh
      updateUI();
    }
  }

  // Pre-update the local model for more responsive UI
  void _preUpdateLocalModel(String action, int? amount, PokerGameModel pokerGame) {
    try {
      // Apply local changes first for responsive UI
      final player = pokerGame.currentPlayer;

      switch (action) {
        case 'fold':
          player.hasFolded = true;
          player.hasActed = true;
          break;
        case 'check':
          player.hasActed = true;
          break;
        case 'call':
          final callAmount = pokerGame.callAmount();
          if (callAmount > 0 && player.chipBalance >= callAmount) {
            player.chipBalance -= callAmount;
            player.currentBet += callAmount;
            pokerGame.pot += callAmount;
            player.hasActed = true;
          }
          break;
        case 'raise':
        case 'bet':
          if (amount != null && player.chipBalance >= amount) {
            player.chipBalance -= amount;
            player.currentBet = amount;
            pokerGame.pot += amount;
            pokerGame.currentBet = amount;
            player.hasActed = true;
          }
          break;
      }

      // Move to the next player locally as well
      int nextPlayerIndex = (pokerGame.currentPlayerIndex + 1) % pokerGame.players.length;

      // Find next active player
      int count = 0;
      while (count < pokerGame.players.length) {
        final nextPlayer = pokerGame.players[nextPlayerIndex];
        if (!nextPlayer.hasFolded && !nextPlayer.isAllIn) {
          break;
        }
        nextPlayerIndex = (nextPlayerIndex + 1) % pokerGame.players.length;
        count++;
      }

      pokerGame.currentPlayerIndex = nextPlayerIndex;
    } catch (e) {
      print('Error in pre-update: $e');
      // Errors here are not critical
    }
  }

  /// Show confirmation message for an action
  void _showActionConfirmationMessage(String action, int? amount, PokerGameModel pokerGame) {
    String message;

    switch (action) {
      case 'check':
        message = 'You checked';
        break;
      case 'call':
        message = 'You called ${pokerGame.currentBet} chips';
        break;
      case 'raise':
        message = 'You raised to ${amount ?? 0} chips';
        break;
      case 'bet':
        message = 'You bet ${amount ?? 0} chips';
        break;
      case 'fold':
        message = 'You folded';
        break;
      default:
        message = 'Action completed';
    }

    showActionSnackBar(message);
  }

  /// Start a new hand
  void startNewHand(PokerGameModel pokerGame, GameService? gameService, String gameId) {
    pokerGame.startNewHand();
    setHandStarted(true);

    // Notify other players
    if (gameService != null) {
      for (int i = 0; i < 3; i++) {
        Future.delayed(Duration(milliseconds: 300 * i), () {
          gameService.notifyPlayerJoined(gameId, pokerGame.gameModel);
        });
      }
    }

    // Force UI update
    updateUI();
  }

  /// Show game rules dialog
  void showRulesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Texas Hold\'em Rules'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Game Flow:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('1. Each player receives 2 private cards (hole cards)'),
                Text('2. Pre-Flop: First round of betting'),
                Text(
                    '3. The Flop: 3 community cards are dealt, followed by betting'),
                Text(
                    '4. The Turn: A 4th community card is dealt, followed by betting'),
                Text(
                    '5. The River: A 5th community card is dealt, followed by betting'),
                Text(
                    '6. Showdown: Players make their best 5-card hand from their hole cards and the community cards'),
                SizedBox(height: 16),
                Text(
                  'Betting Rules:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                    '• Check: Pass the action to the next player (only if no one has bet)'),
                Text(
                    '• Bet/Raise: Place chips in the pot (minimum bet is the big blind)'),
                Text('• Call: Match the current bet to stay in the hand'),
                Text(
                    '• Fold: Discard your hand and forfeit any chance at the pot'),
                SizedBox(height: 16),
                Text(
                  'Hand Rankings (strongest to weakest):',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('1. Royal Flush: A, K, Q, J, 10 of the same suit'),
                Text(
                    '2. Straight Flush: Five sequential cards of the same suit'),
                Text('3. Four of a Kind: Four cards of the same rank'),
                Text(
                    '4. Full House: Three cards of one rank and two of another'),
                Text('5. Flush: Five cards of the same suit'),
                Text('6. Straight: Five sequential cards of mixed suits'),
                Text('7. Three of a Kind: Three cards of the same rank'),
                Text('8. Two Pair: Two different pairs'),
                Text('9. One Pair: Two cards of the same rank'),
                Text('10. High Card: Highest card when no other hand is made'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  /// Show connection status dialog
  void showConnectionStatus(BuildContext context, GameService? gameService,
      PokerGameState gameState, String gameId) {
    final bool isConnected = gameService != null &&
        (gameService.isSocketConnected ?? false);
    final int errorCount = gameState.consecutiveErrors;
    final DateTime? lastUpdate = gameState.lastSuccessfulUpdate;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Connection Status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statusRow('Connected', isConnected ? 'Yes' : 'No',
                  isConnected ? Colors.green : Colors.red),
              _statusRow('Last Update', lastUpdate != null ?
              '${DateTime.now().difference(lastUpdate).inSeconds}s ago' : 'Never',
                  lastUpdate != null && DateTime.now().difference(lastUpdate).inSeconds < 10 ?
                  Colors.green : Colors.orange),
              _statusRow('Errors', errorCount.toString(),
                  errorCount > 0 ? Colors.orange : Colors.green),
              _statusRow('Game ID', gameId, Colors.blue),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();

                // Force reconnection
                if (gameService != null) {
                  final userModel = Provider.of<UserModel>(context, listen: false);
                  if (userModel.authToken != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Forcing reconnection...'),
                        duration: Duration(seconds: 1),
                      ),
                    );

                    gameService.forceStateSynchronization(gameId, userModel.authToken!);

                    // Also force UI update
                    updateUI();
                  }
                }
              },
              child: Text('Force Reconnect'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  /// Manually sync game state with server
  void manualSync(GameService gameService, String gameId, String authToken) {
    print('Manually forcing state synchronization');
    gameService.forceStateSynchronization(gameId, authToken);

    // Update UI immediately
    updateUI();

    // Schedule another update after a short delay to catch any state changes
    Future.delayed(Duration(milliseconds: 500), () {
      updateUI();
    });
  }

  /// Helper to create status row
  Widget _statusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold)),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// Confirm exit game dialog
  Future<void> confirmExitGame(BuildContext context, Function onConfirm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Exit Game?'),
          content: const Text('Are you sure you want to exit this poker game?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Exit Game'),
            ),
          ],
        );
      },
    ) ?? false;

    if (confirmed) {
      onConfirm();
    }
  }

  void handlePlayerAction(String action, PokerGameModel pokerGame,
      UserModel userModel, GameService? gameService, String gameId,
      BuildContext context, {int? amount}) async {

    // First handle the action normally
    await handleAction(action, pokerGame, userModel, gameService, gameId, context, amount: amount);

    // Then force a turn change update to ensure all clients see the turn change
    if (gameService != null && userModel.authToken != null) {
      await TurnChangeHandler.forceTurnChangeUpdate(
          gameId,
          userModel.authToken!,
          gameService,
          context,
          updateUI
      );
    }
  }

  /// Clear cached state data
  void clearCache() {
    _processedEventIds.clear();
    _lastUpdateTime = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}