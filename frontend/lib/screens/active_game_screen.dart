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
  late GameService _gameService;
  late UserModel _userModel;
  int _currentPot = 0;
  int _currentBet = 0;
  final TextEditingController _raiseController = TextEditingController();
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _game = widget.game;
    _currentBet = _game.bigBlind; // Initialize with big blind amount

    // Initialize game service after the build is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGameService();
    });
  }

  void _initializeGameService() {
    // Get user model from provider
    _userModel = Provider.of<UserModel>(context, listen: false);
    if (_userModel.authToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Authentication error. Please log in again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _gameService = GameService();
    // Don't initialize socket again - it should already be connected

    // Make sure we're in the game room
    _gameService.joinGameRoom(_game.id);

    // Listen for player updates with handling for being kicked
    _gameService.listenForPlayerUpdates(_handleGameUpdate, _handlePlayerKicked);
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

      // Check if game is complete
      if (updatedGame.status == GameStatus.completed && _game.status != GameStatus.completed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Game has ended'),
            backgroundColor: Colors.blue,
          ),
        );

        // Return to home screen
        _exiting = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
        return;
      }

      // Check if current player is still in the game
      final currentUserId = _userModel.id;
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

          _exiting = true;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
          return;
        }
      }

      // Update the game state
      setState(() {
        _game = updatedGame;
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
    final result = await _gameService.endGame(_game.id, _userModel.authToken!);

    if (result['success']) {
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
    // Only leave the room if explicitly exiting, not for screen refreshes
    if (!_exiting && _userModel?.authToken != null) {
      _gameService?.leaveGameRoom(_game.id);
    }

    _raiseController.dispose();
    super.dispose();
  }

  void _nextTurn() {
    setState(() {
      _game.nextTurn();
    });
  }

  void _handleCheck() {
    // In a real app, you would make an API call to update the game state
    _nextTurn();
    _showActionSnackBar('Check');
  }

  void _handleCall() {
    final player = _game.currentPlayer;

    if (player.chipBalance >= _currentBet) {
      setState(() {
        player.removeChips(_currentBet);
        _currentPot += _currentBet;
      });

      _nextTurn();
      _showActionSnackBar('Call: $_currentBet chips');
    } else {
      _showInsufficientChipsDialog();
    }
  }

  void _handleFold() {
    setState(() {
      _game.currentPlayer.setInactive();
    });

    _nextTurn();
    _showActionSnackBar('Fold');
  }

  void _handleRaise() {
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
            onPressed: () {
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

              final player = _game.currentPlayer;
              if (player.chipBalance >= raiseAmount) {
                setState(() {
                  player.removeChips(raiseAmount);
                  _currentPot += raiseAmount;
                  _currentBet = raiseAmount;
                });

                _nextTurn();
                Navigator.of(context).pop();
                _showActionSnackBar('Raise: $raiseAmount chips');
              } else {
                Navigator.of(context).pop();
                _showInsufficientChipsDialog();
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
                'Pot: $_currentPot',
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
          if (_userModel?.id == _game.hostId) ...[
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
                        onPressed: _handleFold,
                      ),
                      PokerActionButton(
                        label: 'Check',
                        color: Colors.amber,
                        icon: Icons.check,
                        onPressed: _handleCheck,
                      ),
                      PokerActionButton(
                        label: 'Call',
                        color: Colors.green,
                        icon: Icons.call,
                        onPressed: _handleCall,
                      ),
                      PokerActionButton(
                        label: 'Raise',
                        color: Colors.purple,
                        icon: Icons.arrow_upward,
                        onPressed: _handleRaise,
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