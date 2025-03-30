import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game_model.dart';
import '../models/poker_game_model.dart';
import '../models/user_model.dart';
import '../services/game_service.dart';
import '../widgets/poker_table_widget.dart';
import 'home_screen.dart';

class PokerGameScreen extends StatefulWidget {
  final GameModel game;

  const PokerGameScreen({Key? key, required this.game}) : super(key: key);

  @override
  State<PokerGameScreen> createState() => _PokerGameScreenState();
}

class _PokerGameScreenState extends State<PokerGameScreen> {
  late PokerGameModel _pokerGame;
  GameService? _gameService;
  bool _isInitializing = true;
  String _errorMessage = '';
  bool _isExiting = false;
  bool _handStarted = false;

  @override
  void initState() {
    super.initState();
    _pokerGame = PokerGameModel(gameModel: widget.game);

    // Initialize game service after the first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGameService();
    });
  }

  void _initializeGameService() {
    final userModel = Provider.of<UserModel>(context, listen: false);
    setState(() {
      _isInitializing = true;
      _errorMessage = '';
    });

    if (userModel.authToken == null) {
      setState(() {
        _isInitializing = false;
        _errorMessage = 'Authentication error. Please log in again.';
      });
      return;
    }

    try {
      // Create game service
      _gameService = GameService();

      // Initialize socket connection
      _gameService!.initSocket(
        userModel.authToken!,
        userId: userModel.id,
      );

      // Join the game room for real-time updates
      _gameService!.joinGameRoom(widget.game.id);

      // Listen for game updates
      _gameService!.listenForAllGameUpdates(_handleGameUpdate);

      setState(() {
        _isInitializing = false;
      });

      // Check if game is already in progress
      _checkGameStatus(userModel);

    } catch (e) {
      setState(() {
        _isInitializing = false;
        _errorMessage = 'Error initializing poker game: ${e.toString()}';
      });
    }
  }

  // Check if game is already in progress
  void _checkGameStatus(UserModel userModel) async {
    if (_gameService == null) return;

    try {
      final result = await _gameService!.getGame(widget.game.id, userModel.authToken!);
      if (result['success']) {
        final updatedGame = result['game'] as GameModel;

        // If game is active, update our game state
        if (updatedGame.status == GameStatus.active && !_handStarted) {
          _startNewHandFromExistingGame(updatedGame);
        }
      }
    } catch (e) {
      print('Error checking game status: $e');
    }
  }

  // Start a new hand from existing game data
  void _startNewHandFromExistingGame(GameModel existingGame) {
    setState(() {
      // Update base game model
      _pokerGame.gameModel.status = existingGame.status;
      _pokerGame.gameModel.currentPlayerIndex = existingGame.currentPlayerIndex;
      _pokerGame.gameModel.pot = existingGame.pot;
      _pokerGame.gameModel.currentBet = existingGame.currentBet;

      // Force pokerGame to start a hand if not already in progress
      if (!_pokerGame.handInProgress) {
        _pokerGame.handInProgress = true;
        _handStarted = true;

        // Ensure we have the correct number of players
        _pokerGame.players = existingGame.players
            .map((p) => PokerPlayer.fromPlayer(p))
            .toList();
      }
    });

    // Simulate real-time updates to other players
    _gameService?.notifyPlayerJoined(widget.game.id, _pokerGame.gameModel);
  }

  // Handle game updates from the server
  void _handleGameUpdate(dynamic data) {
    if (data == null) return;

    try {
      // If game data is available, update our model
      if (data['game'] != null) {
        final updatedGame = GameModel.fromJson(data['game']);

        setState(() {
          // Update base game properties
          _pokerGame.gameModel.status = updatedGame.status;
          _pokerGame.gameModel.currentPlayerIndex = updatedGame.currentPlayerIndex;
          _pokerGame.gameModel.pot = updatedGame.pot ?? _pokerGame.gameModel.pot;
          _pokerGame.gameModel.currentBet = updatedGame.currentBet ?? _pokerGame.gameModel.currentBet;

          // Update player data if needed
          if (updatedGame.players.length != _pokerGame.players.length) {
            _pokerGame.players = updatedGame.players
                .map((p) => PokerPlayer.fromPlayer(p))
                .toList();
          }

          // Start a hand if game is active and we haven't started yet
          if (updatedGame.status == GameStatus.active && !_handStarted) {
            _pokerGame.handInProgress = true;
            _handStarted = true;

            // Force a refresh of the UI
            _pokerGame.notifyListeners();
          }
        });
      }

      // Handle specific events
      if (data['action'] == 'game_started' && !_handStarted) {
        setState(() {
          _pokerGame.handInProgress = true;
          _handStarted = true;

          // Force a refresh
          _pokerGame.notifyListeners();
        });
      }

    } catch (e) {
      print('Error handling game update: $e');
    }
  }

  // Start a new hand
  void _startNewHand() {
    setState(() {
      _pokerGame.startNewHand();
      _handStarted = true;
    });

    // Notify other players
    _gameService?.notifyPlayerJoined(widget.game.id, _pokerGame.gameModel);
  }

  // Updated handleAction method for PokerGameScreen
  void _handleAction(String action, {int? amount}) async {
    if (_gameService == null || Provider.of<UserModel>(context, listen: false).authToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Service not initialized'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final userModel = Provider.of<UserModel>(context, listen: false);
    final userId = userModel.id;

    // Update local state first
    setState(() {
      _pokerGame.performAction(action, amount: amount);

      // Check if the hand is over early (everyone folded)
      if (_pokerGame.checkForEarlyWin()) {
        // Hand is over, nothing else to do
        return;
      }
    });

    // Create action event data
    final actionData = {
      'gameId': widget.game.id,
      'action': 'game_action_performed',
      'actionType': action,
      'amount': amount,
      'userId': userId,
      'player': _pokerGame.players.firstWhere((p) => p.userId == userId).username,
      'previousPlayerIndex': _pokerGame.currentPlayerIndex,
      'currentPlayerIndex': (_pokerGame.currentPlayerIndex + 1) % _pokerGame.players.length,
      'game': _pokerGame.gameModel.toJson(),
      'timestamp': DateTime.now().toIso8601String()
    };

    // Send the action to server using socket
    _gameService!.emit('game_action', actionData);

    // Also notify all players about the game state update
    _gameService!.notifyPlayerJoined(widget.game.id, _pokerGame.gameModel);
  }

  @override
  void dispose() {
    if (!_isExiting && _gameService != null) {
      // Leave the game room
      _gameService!.leaveGameRoom(widget.game.id);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userModel = Provider.of<UserModel>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Poker: ${widget.game.name}'),
        actions: [
          // Game ID for sharing
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'ID: ${widget.game.getShortId()}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
            ),
          ),

          // Settings menu
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'rules',
                child: Text('Game Rules'),
              ),
              const PopupMenuItem(
                value: 'exit',
                child: Text('Exit Game'),
              ),
            ],
            onSelected: (value) {
              if (value == 'rules') {
                _showRulesDialog(context);
              } else if (value == 'exit') {
                _confirmExitGame(context);
              }
            },
          ),
        ],
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _initializeGameService(),
              child: const Text('Retry'),
            ),
          ],
        ),
      )
          : ChangeNotifierProvider.value(
        value: _pokerGame,
        child: Consumer<PokerGameModel>(
          builder: (context, pokerGame, child) {
            return PokerTableWidget(
              gameModel: pokerGame,
              currentUserId: userModel.id ?? '',
              onAction: _handleAction,
              onStartNewHand: userModel.id == widget.game.hostId
                  ? _startNewHand
                  : () {},
            );
          },
        ),
      ),
    );
  }

  // Show game rules dialog
  void _showRulesDialog(BuildContext context) {
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
                Text(
                    '1. Each player receives 2 private cards (hole cards)'),
                Text(
                    '2. Pre-Flop: First round of betting'),
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
                Text(
                    '• Call: Match the current bet to stay in the hand'),
                Text(
                    '• Fold: Discard your hand and forfeit any chance at the pot'),
                SizedBox(height: 16),
                Text(
                  'Hand Rankings (strongest to weakest):',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('1. Royal Flush: A, K, Q, J, 10 of the same suit'),
                Text('2. Straight Flush: Five sequential cards of the same suit'),
                Text('3. Four of a Kind: Four cards of the same rank'),
                Text('4. Full House: Three cards of one rank and two of another'),
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

  // Confirm exit game dialog
  void _confirmExitGame(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Exit Game?'),
          content: const Text('Are you sure you want to exit this poker game?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _exitGame();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Exit Game'),
            ),
          ],
        );
      },
    );
  }

  // Exit the game and return to home screen
  void _exitGame() {
    setState(() {
      _isExiting = true;
    });

    // Leave the game room
    if (_gameService != null) {
      _gameService!.leaveGameRoom(widget.game.id);
    }

    // Navigate back to home screen
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
    );
  }
}