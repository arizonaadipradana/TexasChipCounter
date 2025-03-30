import 'dart:math' as Math;

import 'package:flutter/material.dart';
import 'package:nyanguni_kancane/screens/poker_game_screen.dart';
import 'package:provider/provider.dart';

import '../models/game_model.dart';
import '../models/user_model.dart';
import '../services/game_service_core.dart';
import '../widgets/poker_action_button.dart';
import 'home_screen.dart';

class ActiveGameScreen extends StatefulWidget {
  final GameModel game;

  const ActiveGameScreen({Key? key, required this.game}) : super(key: key);

  @override
  State<ActiveGameScreen> createState() => _ActiveGameScreenState();
}

class _ActiveGameScreenState extends State<ActiveGameScreen> {
  late GameModel _game;
  GameService? _gameService;
  UserModel? _userModel;
  int _currentPot = 0;
  int _currentBet = 0;
  final TextEditingController _raiseController = TextEditingController();
  bool _exiting = false;
  bool _isProcessingAction = false;
  bool _refreshingState = false;
  final Set<String> _displayedNotifications = {};
  bool _isShowingNotification = false;

  @override
  void initState() {
    super.initState();
    _game = widget.game;
    // Initialize pot with current game pot value
    _currentPot = _game.pot ?? 0;
    _currentBet = _game.currentBet ?? _game.bigBlind; // Initialize with current bet or big blind amount

    // Initialize game service after the build is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGameService();
    });
  }

  void _initializeGameService() {
    // Get user model from provider
    _userModel = Provider.of<UserModel>(context, listen: false);
    if (_userModel?.authToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Authentication error. Please log in again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _gameService = GameService();

    // Make sure we're in the game room
    _gameService?.joinGameRoom(_game.id);

    // IMPORTANT: Listen for all updates BEFORE setting up specific handlers
    // to avoid socket disconnect issues
    _gameService?.listenForAllGameUpdates(widget.game.id, _handleAnyGameEvent);

    // Set up periodic state refresh to ensure consistency
    // This acts as a fallback in case any real-time events are missed
    _setupPeriodicRefresh();

    // Initial refresh to get the latest state
    _refreshGameState();
  }

  // Set up periodic refresh as a backup for real-time updates
  void _setupPeriodicRefresh() {
    // Refresh game state every 5 seconds as a backup
    Future.delayed(Duration(seconds: 5), () {
      if (mounted && !_exiting) {
        _refreshGameState(silent: true);
        _setupPeriodicRefresh(); // Schedule next refresh
      }
    });
  }

  // Method to fetch the latest game state from the server
  // Added silent parameter to avoid showing loading indicators during background refresh
  Future<void> _refreshGameState({bool silent = false}) async {
    if (_gameService == null || _userModel?.authToken == null || _refreshingState) {
      return;
    }

    if (!silent) {
      setState(() {
        _refreshingState = true;
      });
    }

    try {
      final result = await _gameService!.getGame(_game.id, _userModel!.authToken!);

      if (result['success']) {
        final updatedGame = result['game'] as GameModel;
        setState(() {
          _game = updatedGame;
          _currentPot = updatedGame.pot ?? _currentPot;
          _currentBet = updatedGame.currentBet ?? _currentBet;
          if (!silent) _refreshingState = false;
        });
      }
    } catch (e) {
      print('Error refreshing game state: $e');
    } finally {
      if (mounted && !silent) {
        setState(() {
          _refreshingState = false;
        });
      }
    }
  }

  void _handleAnyGameEvent(dynamic data) {
    if (!mounted) return;

    try {
      print('Received game event: ${data.toString().substring(0, Math.min(100, data.toString().length))}...');
      print('Event type: ${data['action'] ?? 'unknown'}');

      // Check if this is game data we can use
      if (data != null && data['game'] != null) {
        final updatedGame = GameModel.fromJson(data['game']);

        // Preserve the short ID
        updatedGame.shortId = _game.shortId;

        // Log changes for debugging
        print('Current player index: ${_game.currentPlayerIndex} -> ${updatedGame.currentPlayerIndex}');

        // Update pot amount and bet if available
        int newPot = updatedGame.pot ?? _currentPot;
        int newBet = updatedGame.currentBet ?? _currentBet;

        // Check if game is complete
        if (updatedGame.status == GameStatus.completed && _game.status != GameStatus.completed) {
          _showUniqueNotification('game_ended', 'Game has ended', Colors.blue);

          // Clear game ID cache
          GameService.clearGameIdCache();

          // Return to home screen
          _exiting = true;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
          return;
        }

        // Check if current player is still in the game
        final currentUserId = _userModel?.id;
        if (currentUserId != null) {
          final stillInGame = updatedGame.players.any((p) => p.userId == currentUserId);

          if (!stillInGame) {
            print('Current player no longer in game, returning to home');
            _showUniqueNotification('player_removed', 'You are no longer in this game', Colors.red);

            // Clear game ID cache
            GameService.clearGameIdCache();

            _exiting = true;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
            return;
          }

          // Get the current user's player from the updated game
          final updatedPlayer = updatedGame.players.firstWhere(
                  (p) => p.userId == currentUserId,
              orElse: () => _game.players.firstWhere(
                      (p) => p.userId == currentUserId,
                  orElse: () => throw Exception('Player not found')
              )
          );

          // Check if chip balance changed and update the user model
          final currentUser = _userModel!;
          if (updatedPlayer.chipBalance != currentUser.chipBalance) {
            currentUser.updateChipBalance(updatedPlayer.chipBalance);
          }
        }

        // Update the game state
        setState(() {
          _game = updatedGame;
          _currentPot = newPot;
          _currentBet = newBet;
        });

        // For turn changed events, play a sound or add a visual indicator
        if (data['action'] == 'turn_changed' ||
            (data['action'] == 'game_action_performed' && _game.currentPlayerIndex != updatedGame.currentPlayerIndex)) {
          // Get current player name
          final currentPlayerName = updatedGame.currentPlayer.username;

          // Show a subtle notification for turn change
          _showUniqueNotification(
              'turn_changed_${updatedGame.currentPlayerIndex}',
              'It\'s $currentPlayerName\'s turn now',
              Colors.blue.shade700
          );
        }

        // Display action info if available
        if (data['action'] == 'game_action_performed' && data['actionType'] != null) {
          String actionMessage = '';

          // Find the player who performed the action
          if (data['actionType'] != null) {
            if (updatedGame.players.isNotEmpty) {
              // Get the previous player who just acted (use data from event if available)
              int previousPlayerIndex = data['previousPlayerIndex'] ??
                  ((updatedGame.currentPlayerIndex - 1 + updatedGame.players.length) % updatedGame.players.length);

              if (previousPlayerIndex >= 0 && previousPlayerIndex < updatedGame.players.length) {
                final actor = updatedGame.players[previousPlayerIndex];

                actionMessage = '${actor.username} - ${data['actionType']}';
                if (data['amount'] != null && data['amount'] != 0) {
                  actionMessage += ' ${data['amount']} chips';
                }

                _showUniqueNotification(
                    'action_${data['actionType']}_${previousPlayerIndex}_${DateTime.now().millisecondsSinceEpoch}',
                    actionMessage,
                    Colors.grey.shade800
                );
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error handling game event: $e');
      // If we encounter an error processing the event, refresh state from server
      _refreshGameState(silent: true);
    }
  }

  // Helper method to show notifications only once per ID
  void _showUniqueNotification(String notificationId, String message, Color backgroundColor) {
    // Don't show duplicate notifications within a short timeframe
    if (_displayedNotifications.contains(notificationId)) {
      print('Skipping duplicate notification: $notificationId');
      return;
    }

    // Don't show if another notification is currently showing
    if (_isShowingNotification) {
      print('Skipping notification while another is showing');
      return;
    }

    _isShowingNotification = true;
    _displayedNotifications.add(notificationId);

    // After 3 seconds, remove this notification ID from the set
    Future.delayed(Duration(seconds: 3), () {
      if (mounted) {
        _displayedNotifications.remove(notificationId);
      }
    });

    // After 1 second, allow new notifications
    Future.delayed(Duration(seconds: 1), () {
      if (mounted) {
        _isShowingNotification = false;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 1),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleEndGame() async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Game?'),
        content: const Text('Are you sure you want to end the game? This will conclude the current round and return all players to the home screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('End Game'),
          ),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    // Call API to end the game
    if (_gameService == null || _userModel?.authToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Service not initialized'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final result = await _gameService!.endGame(_game.id, _userModel!.authToken!);

    if (result['success']) {
      // Clear game ID cache
      GameService.clearGameIdCache();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Game ended successfully'),
        ),
      );

      // Set flag to prevent unnecessary cleanup in dispose
      _exiting = true;

      // Navigate back to home screen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    // Only attempt cleanup if not navigating to another screen
    if (!_exiting && _gameService != null) {
      // IMPORTANT: Only clean up event listeners without leaving the room
      _gameService!.cleanupGameListeners();

      // We no longer leave the game room here since that's causing disconnection issues
      // The room membership is now managed by the SocketManager singleton
    }

    _raiseController.dispose();
    super.dispose();
  }

  // Use server API to perform check action
  void _handleCheck() async {
    if (_gameService == null || _userModel?.authToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Service not initialized'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isProcessingAction = true;
    });

    final result = await _gameService!.gameAction(
      _game.id,
      'check',
      _userModel!.authToken!,
    );

    setState(() {
      _isProcessingAction = false;
    });

    if (result['success']) {
      // The game will be updated via socket events
      _showActionSnackBar('Check');

      // No need to manually refresh as the real-time events should handle it
      // In case of any sync issues, our periodic refresh will catch it
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Use server API to perform call action
  void _handleCall() async {
    if (_gameService == null || _userModel?.authToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Service not initialized'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // First check if the user has enough chips
    final currentPlayer = _game.players.firstWhere(
            (p) => p.userId == _userModel!.id,
        orElse: () => throw Exception('Player not found')
    );

    if (currentPlayer.chipBalance < _currentBet) {
      _showInsufficientChipsDialog();
      return;
    }

    setState(() {
      _isProcessingAction = true;
    });

    final result = await _gameService!.gameAction(
      _game.id,
      'call',
      _userModel!.authToken!,
    );

    setState(() {
      _isProcessingAction = false;
    });

    if (result['success']) {
      _showActionSnackBar('Call: $_currentBet chips');

      // Update user chip balance locally for immediate feedback
      if (_userModel != null) {
        _userModel!.subtractChips(_currentBet);
      }

      // No need to manually refresh as real-time events will update the UI
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Use server API to perform fold action
  void _handleFold() async {
    if (_gameService == null || _userModel?.authToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Service not initialized'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isProcessingAction = true;
    });

    final result = await _gameService!.gameAction(
      _game.id,
      'fold',
      _userModel!.authToken!,
    );

    setState(() {
      _isProcessingAction = false;
    });

    if (result['success']) {
      _showActionSnackBar('Fold');

      // No need to manually refresh as real-time events will update the UI
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Use server API to perform raise action
  void _handleRaise() {
    if (_gameService == null || _userModel?.authToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Service not initialized'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // First check if the user has enough chips for the minimum raise
    final currentPlayer = _game.players.firstWhere(
            (p) => p.userId == _userModel!.id,
        orElse: () => throw Exception('Player not found')
    );

    if (currentPlayer.chipBalance < _currentBet * 2) {
      _showInsufficientChipsDialog();
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Raise Amount'),
        content: TextField(
          controller: _raiseController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Min: ${_currentBet * 2}',
            suffixText: 'chips',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final raiseAmount = int.tryParse(_raiseController.text) ?? 0;
              if (raiseAmount < _currentBet * 2) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Raise must be at least ${_currentBet * 2} chips'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              // Check if player has enough chips for the raise
              if (raiseAmount > currentPlayer.chipBalance) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('You don\'t have enough chips for this raise'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              Navigator.of(context).pop();

              setState(() {
                _isProcessingAction = true;
              });

              final result = await _gameService!.gameAction(
                _game.id,
                'raise',
                _userModel!.authToken!,
                amount: raiseAmount,
              );

              setState(() {
                _isProcessingAction = false;
              });

              if (result['success']) {
                _showActionSnackBar('Raise: $raiseAmount chips');

                // Update user chip balance locally for immediate feedback
                if (_userModel != null) {
                  _userModel!.subtractChips(raiseAmount);
                }

                // Force refresh game state after a short delay
                Future.delayed(Duration(milliseconds: 500), () {
                  _refreshGameState();
                });
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result['message']),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Raise'),
          ),
        ],
      ),
    );
  }

  void _showActionSnackBar(String action) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_game.players[(_game.currentPlayerIndex - 1) % _game.players.length].username} - $action'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showInsufficientChipsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Insufficient Chips'),
        content: const Text('You don\'t have enough chips for this action.'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userModel = Provider.of<UserModel>(context);
    final isCurrentUserTurn = _game.currentPlayer.userId == userModel.id;

    return PokerGameScreen(game: widget.game);
  }
}