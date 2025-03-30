import 'dart:async';

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
  Timer? _refreshTimer; // Timer for periodic refresh

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

      // Setup periodic refresh to ensure game state stays in sync
      _setupPeriodicRefresh();

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

  // Setup periodic refresh to keep game state in sync
  void _setupPeriodicRefresh() {
    // Cancel any existing timer
    _refreshTimer?.cancel();

    // Set up new timer - refresh every 3 seconds as a backup
    _refreshTimer = Timer.periodic(Duration(seconds: 3), (timer) {
      if (mounted && !_isExiting) {
        // Silently refresh the game state
        _refreshGameState(silent: true);
      } else {
        // Cancel timer if widget is disposed
        timer.cancel();
      }
    });
  }

  // Explicitly refresh game state from the server
  Future<void> _refreshGameState({bool silent = false}) async {
    if (_gameService == null ||
        Provider.of<UserModel>(context, listen: false).authToken == null) {
      return;
    }

    try {
      final userModel = Provider.of<UserModel>(context, listen: false);
      final result =
          await _gameService!.getGame(widget.game.id, userModel.authToken!);

      if (result['success'] && mounted) {
        final updatedGame = result['game'] as GameModel;

        // Update the UI with the latest game state
        setState(() {
          // Update base game properties
          _pokerGame.gameModel.status = updatedGame.status;
          _pokerGame.gameModel.currentPlayerIndex =
              updatedGame.currentPlayerIndex;
          _pokerGame.gameModel.pot =
              updatedGame.pot ?? _pokerGame.gameModel.pot;
          _pokerGame.gameModel.currentBet =
              updatedGame.currentBet ?? _pokerGame.gameModel.currentBet;

          // Make sure the short ID is preserved
          if (_pokerGame.gameModel.shortId == null &&
              updatedGame.shortId != null) {
            _pokerGame.gameModel.shortId = updatedGame.shortId;
          }

          // Notify listeners that the game state has changed
          _pokerGame.notifyListeners();
        });
      }
    } catch (e) {
      print('Error refreshing game state: $e');
    }
  }

  // Check if game is already in progress
  void _checkGameStatus(UserModel userModel) async {
    if (_gameService == null) return;

    try {
      final result =
          await _gameService!.getGame(widget.game.id, userModel.authToken!);
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

  void _handleGameAction(dynamic data) {
    try {
      final actionType = data['actionType'];
      final amount = data['amount'];
      final playerIndex = data['previousPlayerIndex'] ??
          (_pokerGame.currentPlayerIndex > 0 ?
          _pokerGame.currentPlayerIndex - 1 :
          _pokerGame.players.length - 1);

      if (playerIndex >= 0 && playerIndex < _pokerGame.players.length) {
        final player = _pokerGame.players[playerIndex];

        setState(() {
          // Update player state based on action type
          switch (actionType) {
            case 'fold':
              player.hasFolded = true;
              break;
            case 'bet':
            case 'raise':
              if (amount != null) {
                // Convert to int first
                final amountInt = amount is int ? amount : (amount as num).toInt();
                player.currentBet = amountInt;
                // Update pot directly for immediate visual feedback
                _pokerGame.pot += amountInt;
                // Update local pot value
                _pokerGame.gameModel.pot = _pokerGame.pot;
                // Update current bet amount
                _pokerGame.gameModel.currentBet = amountInt;
              }
              break;
            case 'call':
              final callAmount = data['amount'] ?? _pokerGame.gameModel.currentBet;
              // Convert to int first
              final callAmountInt = callAmount is int ? callAmount : (callAmount as num).toInt();
              player.currentBet = callAmountInt;
              // Update pot for immediate visual feedback
              _pokerGame.pot += callAmountInt;
              // Update local pot value
              _pokerGame.gameModel.pot = _pokerGame.pot;
              break;
          }
        });

        // Display action notification
        String actionMessage = '${player.username} ';
        if (actionType == 'fold') {
          actionMessage += 'folded';
        } else if (actionType == 'check') {
          actionMessage += 'checked';
        } else if (actionType == 'call') {
          actionMessage += 'called ${_pokerGame.gameModel.currentBet} chips';
        } else if (actionType == 'bet') {
          actionMessage += 'bet $amount chips';
        } else if (actionType == 'raise') {
          actionMessage += 'raised to $amount chips';
        }

        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(actionMessage),
              duration: const Duration(seconds: 2),
            )
        );
      }
    } catch (e) {
      print('Error handling game action: $e');
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
        _pokerGame.players =
            existingGame.players.map((p) => PokerPlayer.fromPlayer(p)).toList();
      }
    });

    // Simulate real-time updates to other players
    _gameService?.notifyPlayerJoined(widget.game.id, _pokerGame.gameModel);
  }

  // Handle game updates from the server
  void _handleGameUpdate(dynamic data) {
    if (data == null || !mounted) return;

    try {
      // Special handling for force_refresh events
      if (data['action'] == 'force_refresh') {
        print('Handling force_refresh event');
        setState(() {
          // Just trigger a rebuild
        });

        // Force the poker game model to notify listeners
        _pokerGame.notifyListeners();
        return;
      }

      // If game data is available, update our model
      if (data['game'] != null) {
        final updatedGame = GameModel.fromJson(data['game']);

        // Log the updated state for debugging
        print('Game update received: Current player index: ${updatedGame.currentPlayerIndex}, Status: ${updatedGame.status}');
        print('Pot updated: ${updatedGame.pot}, Current bet: ${updatedGame.currentBet}');

        // Force UI update with setState
        setState(() {
          // Update base game properties
          _pokerGame.gameModel.status = updatedGame.status;
          _pokerGame.gameModel.currentPlayerIndex = updatedGame.currentPlayerIndex;
          _pokerGame.gameModel.pot = updatedGame.pot ?? _pokerGame.gameModel.pot;
          _pokerGame.gameModel.currentBet = updatedGame.currentBet ?? _pokerGame.gameModel.currentBet;

          // Update player data
          if (updatedGame.players.isNotEmpty) {
            // Check if player count changed (someone joined/left)
            if (updatedGame.players.length != _pokerGame.players.length) {
              print('Player count changed: ${_pokerGame.players.length} -> ${updatedGame.players.length}');
              // Update entire player list
              _pokerGame.players = updatedGame.players
                  .map((p) => PokerPlayer.fromPlayer(p))
                  .toList();
            } else {
              // Update each player's data
              for (final updatedPlayer in updatedGame.players) {
                final existingPlayerIndex = _pokerGame.players.indexWhere(
                        (p) => p.userId == updatedPlayer.userId
                );

                if (existingPlayerIndex >= 0) {
                  // Update important properties
                  _pokerGame.players[existingPlayerIndex].chipBalance = updatedPlayer.chipBalance;

                  // Check if there's bet information from the current round
                  if (data['action'] == 'game_action_performed' ||
                      data['action'] == 'turn_changed') {
                    // Find the player who acted
                    if (data['previousPlayerIndex'] != null &&
                        data['previousPlayerIndex'] < _pokerGame.players.length) {
                      final actingPlayerIndex = data['previousPlayerIndex'];
                      final actionType = data['actionType'];

                      if (actionType == 'bet' || actionType == 'raise' || actionType == 'call') {
                        int betAmount = 0;

                        if (actionType == 'bet' || actionType == 'raise') {
                          betAmount = data['amount'] is int
                              ? data['amount']
                              : (data['amount'] as num?)?.toInt() ?? 0;
                        } else if (actionType == 'call') {
                          // Handle nullable currentBet
                          betAmount = _pokerGame.gameModel.currentBet ?? 0;
                        }

                        if (betAmount > 0) {
                          _pokerGame.players[actingPlayerIndex].currentBet = betAmount;
                        }
                      } else if (actionType == 'fold') {
                        _pokerGame.players[actingPlayerIndex].hasFolded = true;
                      }
                    }
                  }
                }
              }
            }
          }

          // Start a hand if game is active and we haven't started yet
          if (updatedGame.status == GameStatus.active && !_handStarted) {
            _pokerGame.handInProgress = true;
            _handStarted = true;
          }
        });

        // Show turn change notification
        if (data['action'] == 'turn_changed' ||
            (data['action'] == 'game_action_performed' &&
                data['currentPlayerIndex'] != null)) {

          final playerIndex = data['currentPlayerIndex'] ?? _pokerGame.currentPlayerIndex;
          if (playerIndex < _pokerGame.players.length) {
            final playerName = _pokerGame.players[playerIndex].username;
            _showTurnChangeNotification(playerName);
          }
        }

        // Force a refresh of the UI
        _pokerGame.notifyListeners();
      }

      // Handle specific game action events
      if (data['action'] == 'game_action_performed' && data['actionType'] != null) {
        _handleGameAction(data);
      }

    } catch (e) {
      print('Error handling game update: $e');
      // If we encounter an error processing the event, refresh state from server
      _refreshGameState(silent: true);
    }
  }

  // Show notification for turn change
  void _showTurnChangeNotification(String playerName) {
    if (!mounted) return;

    // Use WidgetsBinding to ensure the notification appears after the frame is drawn
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("It's $playerName's turn"),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
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
    if (_gameService == null ||
        Provider.of<UserModel>(context, listen: false).authToken == null) {
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

    try {
      // Call the server API to perform the action
      final result = await _gameService!.gameAction(
        widget.game.id,
        action,
        userModel.authToken!,
        amount: amount,
      );

      if (result['success']) {
        // Update local state after server confirms success
        setState(() {
          // Get the updated game model from the response
          final updatedGame = result['game'] as GameModel;

          // Update our local game model
          _pokerGame.gameModel.currentPlayerIndex =
              updatedGame.currentPlayerIndex;
          _pokerGame.gameModel.pot =
              updatedGame.pot ?? _pokerGame.gameModel.pot;
          _pokerGame.gameModel.currentBet =
              updatedGame.currentBet ?? _pokerGame.gameModel.currentBet;

          // Record the action in local history
          _pokerGame.performAction(action, amount: amount);

          // Check if the hand is over early (everyone folded)
          if (_pokerGame.checkForEarlyWin()) {
            // Hand is over, nothing else to do
            return;
          }
        });

        // Show a confirmation message
        _showActionConfirmationMessage(action, amount);

        // Force refresh of game state after a short delay to ensure all clients are synchronized
        Future.delayed(Duration(milliseconds: 500), () {
          if (mounted) {
            _refreshGameState();
          }
        });
      } else {
        // Show error message if the action failed
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Action failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      // Handle API errors specifically
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
    }
  }

  // Show confirmation message for action
  void _showActionConfirmationMessage(String action, int? amount) {
    String message;

    switch (action) {
      case 'check':
        message = 'You checked';
        break;
      case 'call':
        message = 'You called ${_pokerGame.currentBet} chips';
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    // Cancel refresh timer
    _refreshTimer?.cancel();

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

          // Refresh button
          IconButton(
            icon: Icon(Icons.refresh),
            tooltip: 'Refresh game state',
            onPressed: () => _refreshGameState(),
          ),

          // Add Sync button in the app bar
          IconButton(
            icon: Icon(Icons.info_outline),
            tooltip: 'Check connection status',
            onPressed: () {
              if (_gameService != null) {
                _gameService!.checkSocketStatus(widget.game.id).then((status) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Connected: ${status['isConnected']}, In room: ${status['isInRoom']}'),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                });
              }
            },
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
              gameId: widget.game.id,
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
