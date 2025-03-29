import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game_model.dart';
import '../models/user_model.dart';
import '../services/game_service.dart';
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
    _gameService?.listenForAllGameUpdates(_handleAnyGameEvent);
  }

  void _handleAnyGameEvent(dynamic data) {
    if (!mounted) return;

    try {
      // Check if this is game data we can use
      if (data != null && data['game'] != null) {
        final updatedGame = GameModel.fromJson(data['game']);

        // Update pot amount and bet if available
        int newPot = updatedGame.pot ?? _currentPot;
        int newBet = updatedGame.currentBet ?? _currentBet;

        // Check if game is complete
        if (updatedGame.status == GameStatus.completed && _game.status != GameStatus.completed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Game has ended'),
              backgroundColor: Colors.blue,
            ),
          );

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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You are no longer in this game'),
                backgroundColor: Colors.red,
              ),
            );

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

        // Display action info if available
        if (data['action'] == 'game_action_performed' && data['actionType'] != null) {
          String actionMessage = '';

          // Find the player who performed the action
          if (data['actionType'] != null) {
            if (updatedGame.players.isNotEmpty) {
              // Get the previous player who just acted
              int previousPlayerIndex = (updatedGame.currentPlayerIndex - 1);
              if (previousPlayerIndex < 0) previousPlayerIndex = updatedGame.players.length - 1;

              if (previousPlayerIndex >= 0 && previousPlayerIndex < updatedGame.players.length) {
                final actor = updatedGame.players[previousPlayerIndex];

                actionMessage = '${actor.username} - ${data['actionType']}';
                if (data['amount'] != null && data['amount'] != 0) {
                  actionMessage += ' ${data['amount']} chips';
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(actionMessage),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error handling game event: $e');
    }
  }

  void _handleGameAction(dynamic data) {
    if (!mounted) return;

    try {
      // Check if this is a pot-affecting action
      if (data != null && data['game'] != null) {
        final updatedGame = GameModel.fromJson(data['game']);

        // Update pot amount
        setState(() {
          _currentPot = updatedGame.pot ?? _currentPot;
          _currentBet = updatedGame.currentBet ?? _currentBet;
        });

        // Also update the full game model
        _handleGameUpdate(updatedGame);

        // Show a snackbar with the action if provided
        if (data['actionType'] != null && data['player'] != null) {
          String actionMessage = '${data['player']} - ${data['actionType']}';
          if (data['amount'] != null) {
            actionMessage += ' ${data['amount']} chips';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(actionMessage),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('Error handling game action: $e');
    }
  }

  void _handlePlayerKicked(String gameId, String kickedBy) {
    // This is called when the current user is kicked
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have been removed from the game'),
          backgroundColor: Colors.red,
        ),
      );

      // Navigate back to home
      _exiting = true;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
      );
    }
  }

  void _handleGameUpdate(GameModel updatedGame) {
    if (mounted) {
      // Log the update for debugging
      print('Received game update in active game: ${updatedGame.players.length} players');
      print('Game status: ${updatedGame.status}');

      // Update pot value
      final newPot = updatedGame.pot ?? _currentPot;
      final newBet = updatedGame.currentBet ?? _currentBet;

      // Check if game is complete
      if (updatedGame.status == GameStatus.completed && _game.status != GameStatus.completed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Game has ended'),
            backgroundColor: Colors.blue,
          ),
        );

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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You are no longer in this game'),
              backgroundColor: Colors.red,
            ),
          );

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

    return Scaffold(
      appBar: AppBar(
        title: Text(_game.name),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: Text(
                'Pot: $_currentPot chips',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Players',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _game.players.length,
                      itemBuilder: (context, index) {
                        final player = _game.players[index];
                        final isCurrentUser = player.userId == userModel.id;
                        final isCurrentTurn = index == _game.currentPlayerIndex;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: isCurrentTurn ? Colors.blue.shade100 : null,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isCurrentTurn ? Colors.blue : Colors.grey,
                              child: Text(
                                player.username.substring(0, 1).toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(
                              '${player.username} ${isCurrentUser ? '(You)' : ''}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text('${player.chipBalance} chips'),
                            trailing: isCurrentTurn
                                ? const Icon(Icons.arrow_forward, color: Colors.blue)
                                : null,
                            // Show an inactive indicator for folded players
                            enabled: player.isActive,
                            tileColor: !player.isActive ? Colors.grey.shade100 : null,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // End game button (for host only)
          if (userModel.id == _game.hostId) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              color: Colors.amber.shade50,
              child: ElevatedButton.icon(
                onPressed: _handleEndGame,
                icon: const Icon(Icons.stop_circle, color: Colors.white),
                label: const Text('End Game'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],

          if (isCurrentUserTurn) ...[
            Container(
              padding: const EdgeInsets.all(16.0),
              color: Colors.grey.shade200,
              child: Column(
                children: [
                  Text(
                    'Current Bet: $_currentBet chips',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      PokerActionButton(
                        label: 'Fold',
                        color: Colors.red,
                        icon: Icons.close,
                        onPressed: _isProcessingAction ? null : _handleFold,
                      ),
                      PokerActionButton(
                        label: 'Check',
                        color: Colors.amber,
                        icon: Icons.check,
                        onPressed: _isProcessingAction ? null : _handleCheck,
                      ),
                      PokerActionButton(
                        label: 'Call',
                        color: Colors.green,
                        icon: Icons.call,
                        onPressed: _isProcessingAction ? null : _handleCall,
                      ),
                      PokerActionButton(
                        label: 'Raise',
                        color: Colors.purple,
                        icon: Icons.arrow_upward,
                        onPressed: _isProcessingAction ? null : _handleRaise,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16.0),
              color: Colors.grey.shade200,
              child: Center(
                child: Text(
                  'Waiting for ${_game.currentPlayer.username} to play...',
                  style: const TextStyle(
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}