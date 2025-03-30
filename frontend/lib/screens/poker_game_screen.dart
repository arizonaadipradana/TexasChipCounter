// in poker_game_screen.dart

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

class _PokerGameScreenState extends State<PokerGameScreen> with WidgetsBindingObserver {
  late PokerGameModel _pokerGame;
  GameService? _gameService;
  bool _isInitializing = true;
  String _errorMessage = '';
  bool _isExiting = false;
  bool _handStarted = false;

  // Enhanced state management
  Timer? _refreshTimer;
  Timer? _uiUpdateTimer;
  int _lastKnownPlayerIndex = -1;
  bool _forcedRefreshInProgress = false;
  int _consecutiveErrors = 0;
  DateTime? _lastSuccessfulUpdate;

  @override
  void initState() {
    super.initState();
    _pokerGame = PokerGameModel(gameModel: widget.game);

    // Register for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);

    // Initialize game service after the first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGameService();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app comes back to foreground, force refresh
    if (state == AppLifecycleState.resumed) {
      print('App resumed, forcing game state refresh');

      if (_gameService != null && !_isExiting) {
        final userModel = Provider.of<UserModel>(context, listen: false);
        if (userModel.authToken != null) {
          _forceStateRefresh(userModel.authToken!);
        }
      }
    }
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

      // Initialize socket connection with enhanced reliability
      _gameService!.initSocket(
        userModel.authToken!,
        userId: userModel.id,
      );

      // Join the game room for real-time updates
      _gameService!.joinGameRoom(widget.game.id);

      // Listen for all game updates with the specific game ID
      _gameService!.listenForAllGameUpdates(widget.game.id, _handleGameUpdate);

      // Setup UI update timer (updates UI every 500ms regardless of events)
      _setupUiUpdateTimer();

      // Setup periodic forced refresh (every 5 seconds)
      _setupForcedRefreshTimer(userModel.authToken!);

      setState(() {
        _isInitializing = false;
      });

      // Immediately force a state refresh to ensure latest data
      _forceStateRefresh(userModel.authToken!);
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _errorMessage = 'Error initializing poker game: ${e.toString()}';
      });
    }
  }

  // Force a refresh of game state from server
  void _forceStateRefresh(String authToken) async {
    if (_forcedRefreshInProgress) return;

    _forcedRefreshInProgress = true;

    try {
      print('Forcing state refresh for game: ${widget.game.id}');

      final result = await _gameService!.getGame(widget.game.id, authToken);

      if (result['success'] && mounted) {
        final updatedGame = result['game'] as GameModel;

        // Track player index change
        final oldPlayerIndex = _pokerGame.gameModel.currentPlayerIndex;
        final newPlayerIndex = updatedGame.currentPlayerIndex;

        setState(() {
          // Update base game properties
          _pokerGame.gameModel.status = updatedGame.status;
          _pokerGame.gameModel.currentPlayerIndex = updatedGame.currentPlayerIndex;
          _pokerGame.gameModel.pot = updatedGame.pot ?? _pokerGame.gameModel.pot;
          _pokerGame.gameModel.currentBet = updatedGame.currentBet ?? _pokerGame.gameModel.currentBet;

          // Start a hand if game is active and we haven't started yet
          if (updatedGame.status == GameStatus.active && !_handStarted) {
            _pokerGame.handInProgress = true;
            _handStarted = true;
          }

          // Reset error counter on successful update
          _consecutiveErrors = 0;
          _lastSuccessfulUpdate = DateTime.now();
        });

        // If player index changed, update UI and show notification
        if (oldPlayerIndex != newPlayerIndex) {
          _lastKnownPlayerIndex = newPlayerIndex;

          _updateTableWidget();

          // Show turn change notification if appropriate
          if (newPlayerIndex < _pokerGame.players.length) {
            final playerName = _pokerGame.players[newPlayerIndex].username;
            final isCurrentUserTurn = _pokerGame.players[newPlayerIndex].userId ==
                Provider.of<UserModel>(context, listen: false).id;

            _showTurnChangeNotification(
                isCurrentUserTurn ? 'Your turn!' : 'It\'s $playerName\'s turn',
                isCurrentUserTurn ? Colors.green : Colors.blue
            );
          }
        }
      } else {
        _consecutiveErrors++;
        print('Failed to refresh state: ${result['message'] ?? 'Unknown error'}');

        // If too many consecutive errors, force reconnection
        if (_consecutiveErrors >= 3) {
          _gameService!.forceStateSynchronization(widget.game.id, authToken);
          _consecutiveErrors = 0;
        }
      }
    } catch (e) {
      _consecutiveErrors++;
      print('Error in forced refresh: $e');
    } finally {
      _forcedRefreshInProgress = false;
    }
  }

  // Setup a timer to periodically update the UI
  void _setupUiUpdateTimer() {
    _uiUpdateTimer?.cancel();

    // Update UI every 500ms to ensure smoothness
    _uiUpdateTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      if (mounted && !_isExiting) {
        // Only trigger UI update if the state has likely changed
        if (_lastKnownPlayerIndex != _pokerGame.gameModel.currentPlayerIndex) {
          _lastKnownPlayerIndex = _pokerGame.gameModel.currentPlayerIndex;
          _updateTableWidget();
        }
      } else {
        timer.cancel();
      }
    });
  }

  // Setup forced refresh timer
  void _setupForcedRefreshTimer(String authToken) {
    _refreshTimer?.cancel();

    // Force refresh every 5 seconds
    _refreshTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (mounted && !_isExiting && !_forcedRefreshInProgress) {
        // Check if it's been too long since last successful update
        bool needsRefresh = true;

        if (_lastSuccessfulUpdate != null) {
          final timeSinceUpdate = DateTime.now().difference(_lastSuccessfulUpdate!);

          // If recently updated successfully, may not need refresh
          if (timeSinceUpdate.inSeconds < 3) {
            needsRefresh = false;
          }
        }

        if (needsRefresh) {
          _forceStateRefresh(authToken);
        }
      } else if (_isExiting) {
        timer.cancel();
      }
    });
  }

  // Update the poker table widget
  void _updateTableWidget() {
    if (!mounted) return;

    // Force the poker game model to notify listeners
    _pokerGame.notifyListeners();

    // Find and update the poker table widget
    final pokerTableWidgetState = findPokerTableWidgetState(context);
    if (pokerTableWidgetState != null) {
      try {
        final method = pokerTableWidgetState.runtimeType.toString().contains('_PokerTableWidgetState')
            ? pokerTableWidgetState.updateTable : null;
        if (method != null) {
          method();
        }
      } catch (e) {
        print('Could not call update method: $e');
      }
    }
  }

  // Handle game updates with enhanced reliability
  void _handleGameUpdate(dynamic data) {
    if (data == null || !mounted || _isExiting) return;

    try {
      final eventType = data['action'] ?? 'unknown';
      print('Game event received: $eventType');

      // Update last successful update time
      _lastSuccessfulUpdate = DateTime.now();

      // Reset error counter
      _consecutiveErrors = 0;

      // If game data is available, update our model
      if (data['game'] != null) {
        final updatedGame = GameModel.fromJson(data['game']);

        // Track if player index changed
        final oldPlayerIndex = _pokerGame.gameModel.currentPlayerIndex;
        final newPlayerIndex = updatedGame.currentPlayerIndex;
        bool playerIndexChanged = oldPlayerIndex != newPlayerIndex;

        // Force UI update with setState
        setState(() {
          // Update base game properties
          _pokerGame.gameModel.status = updatedGame.status;
          _pokerGame.gameModel.currentPlayerIndex = updatedGame.currentPlayerIndex;
          _pokerGame.gameModel.pot = updatedGame.pot ?? _pokerGame.gameModel.pot;
          _pokerGame.gameModel.currentBet = updatedGame.currentBet ?? _pokerGame.gameModel.currentBet;

          // Update player data more aggressively
          if (updatedGame.players.isNotEmpty) {
            // Update players from the fresh data
            for (int i = 0; i < _pokerGame.players.length && i < updatedGame.players.length; i++) {
              final updatedPlayer = updatedGame.players[i];

              // Update important player properties
              _pokerGame.players[i].chipBalance = updatedPlayer.chipBalance;

              // Handle action-specific updates
              if (data['action'] == 'game_action_performed' &&
                  data['actionType'] != null &&
                  data['previousPlayerIndex'] != null &&
                  data['previousPlayerIndex'] == i) {

                switch(data['actionType']) {
                  case 'bet':
                  case 'raise':
                    if (data['amount'] != null) {
                      _pokerGame.players[i].currentBet =
                      (data['amount'] is int) ? data['amount'] : int.parse(data['amount'].toString());
                    }
                    break;
                  case 'call':
                    _pokerGame.players[i].currentBet = _pokerGame.gameModel.currentBet ?? 0;
                    break;
                  case 'fold':
                    _pokerGame.players[i].hasFolded = true;
                    break;
                }
              }
            }
          }

          // Start hand if needed
          if (updatedGame.status == GameStatus.active && !_handStarted) {
            _pokerGame.handInProgress = true;
            _handStarted = true;
          }

          // Save last known player index
          if (playerIndexChanged) {
            _lastKnownPlayerIndex = newPlayerIndex;
          }
        });

        // If player index changed, update UI and show notification
        if (playerIndexChanged) {
          _updateTableWidget();

          // Show turn change notification
          if (newPlayerIndex < _pokerGame.players.length) {
            final playerName = _pokerGame.players[newPlayerIndex].username;
            final isCurrentUserTurn = _pokerGame.players[newPlayerIndex].userId ==
                Provider.of<UserModel>(context, listen: false).id;

            _showTurnChangeNotification(
                isCurrentUserTurn ? 'Your turn!' : 'It\'s $playerName\'s turn',
                isCurrentUserTurn ? Colors.green : Colors.blue
            );
          }
        }
      }

      // Handle game action with improved reliability
      if (data['action'] == 'game_action_performed' && data['actionType'] != null) {
        _handleGameAction(data);
      }
    } catch (e) {
      _consecutiveErrors++;
      print('Error handling game update: $e');

      // If too many consecutive errors, force reconnection
      if (_consecutiveErrors >= 3 && _gameService != null) {
        final userModel = Provider.of<UserModel>(context, listen: false);
        if (userModel.authToken != null) {
          _gameService!.forceStateSynchronization(widget.game.id, userModel.authToken!);
          _consecutiveErrors = 0;
        }
      }
    }
  }

  // Handle game actions with improved error handling
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

                // Update pot and current bet
                _pokerGame.pot += amountInt;
                _pokerGame.gameModel.pot = _pokerGame.pot;
                _pokerGame.gameModel.currentBet = amountInt;
              }
              break;
            case 'call':
              final callAmount = data['amount'] ?? _pokerGame.gameModel.currentBet;
              // Convert to int first
              final callAmountInt = callAmount is int ? callAmount : (callAmount as num).toInt();
              player.currentBet = callAmountInt;

              // Update pot
              _pokerGame.pot += callAmountInt;
              _pokerGame.gameModel.pot = _pokerGame.pot;
              break;
          }
        });

        // Force table update
        _updateTableWidget();

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

        _showActionSnackBar(actionMessage);
      }
    } catch (e) {
      print('Error handling game action: $e');
    }
  }

  // Enhanced turn change notification
  void _showTurnChangeNotification(String message, Color color) {
    if (!mounted) return;

    // Use WidgetsBinding to ensure the notification appears after the frame is drawn
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.arrow_forward, color: Colors.white),
              SizedBox(width: 8),
              Text(message, style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: color,
          action: SnackBarAction(
            label: 'Update',
            textColor: Colors.white,
            onPressed: () {
              // Force a state refresh when user taps the action
              final userModel = Provider.of<UserModel>(context, listen: false);
              if (userModel.authToken != null) {
                _forceStateRefresh(userModel.authToken!);
              }
            },
          ),
        ),
      );
    });
  }

  void _showActionSnackBar(String action) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(action),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Find PokerTableWidget state in the widget tree
  dynamic findPokerTableWidgetState(BuildContext context) {
    dynamic result;

    void visitor(Element element) {
      if (element.widget.runtimeType.toString().contains('PokerTableWidget')) {
        // We found the widget, now get its state
        final state = (element as StatefulElement).state;
        if (state.runtimeType.toString().contains('_PokerTableWidgetState')) {
          result = state;
          return;
        }
      }

      element.visitChildren(visitor);
    }

    try {
      if (context != null) {
        context.visitChildElements(visitor);
      }
    } catch (e) {
      print('Error finding PokerTableWidget: $e');
    }

    return result;
  }

  @override
  void dispose() {
    // Unregister lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // Cancel timers
    _refreshTimer?.cancel();
    _uiUpdateTimer?.cancel();

    if (!_isExiting && _gameService != null) {
      // Leave the game room
      _gameService!.leaveGameRoom(widget.game.id);

      // Clean up resources
      _gameService!.dispose();
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
          // Sync button
          IconButton(
            icon: Icon(Icons.sync),
            tooltip: 'Sync game state',
            onPressed: () {
              if (_gameService != null && userModel.authToken != null) {
                // Show syncing indicator
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white
                            )
                        ),
                        SizedBox(width: 8),
                        Text('Syncing game state...'),
                      ],
                    ),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );

                // Force state synchronization
                _gameService!.forceStateSynchronization(widget.game.id, userModel.authToken!);
              }
            },
          ),

          // Settings menu
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'status',
                child: Text('Connection Status'),
              ),
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
              } else if (value == 'status') {
                _showConnectionStatus(context);
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
              gameService: _gameService,
            );
          },
        ),
      ),
    );
  }

  // Show connection status dialog
  void _showConnectionStatus(BuildContext context) {
    final userModel = Provider.of<UserModel>(context, listen: false);
    final bool isConnected = _gameService != null &&
        (_gameService!.isSocketConnected ?? false);
    final int errorCount = _consecutiveErrors;
    final DateTime? lastUpdate = _lastSuccessfulUpdate;

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
              _statusRow('Game ID', widget.game.id, Colors.blue),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();

                // Force reconnection
                if (_gameService != null && userModel.authToken != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Forcing reconnection...'),
                      duration: Duration(seconds: 1),
                    ),
                  );

                  _gameService!.forceStateSynchronization(widget.game.id, userModel.authToken!);
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

  // Helper to create status row
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

  // Start a new hand with improved reliability
  void _startNewHand() {
    setState(() {
      _pokerGame.startNewHand();
      _handStarted = true;
    });

    // Notify other players multiple times for reliability
    if (_gameService != null) {
      for (int i = 0; i < 3; i++) {
        Future.delayed(Duration(milliseconds: 300 * i), () {
          _gameService!.notifyPlayerJoined(widget.game.id, _pokerGame.gameModel);
        });
      }
    }
  }

  // Handle player actions with enhanced reliability
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

      // Call the server API with enhanced reliability
      final result = await _gameService!.gameAction(
        widget.game.id,
        action,
        userModel.authToken!,
        amount: amount,
      );

      if (result['success']) {
        // Update UI immediately for responsive feel
        setState(() {
          // Get the updated game model
          final updatedGame = result['game'] as GameModel;

          // Track player index change
          final oldPlayerIndex = _pokerGame.gameModel.currentPlayerIndex;
          final newPlayerIndex = updatedGame.currentPlayerIndex;

          // Update model
          _pokerGame.gameModel.currentPlayerIndex = newPlayerIndex;
          _pokerGame.gameModel.pot = updatedGame.pot ?? _pokerGame.gameModel.pot;
          _pokerGame.gameModel.currentBet = updatedGame.currentBet ?? _pokerGame.gameModel.currentBet;

          // Record the action locally
          _pokerGame.performAction(action, amount: amount);

          // Save last known player index
          _lastKnownPlayerIndex = newPlayerIndex;

          // Update last successful update time
          _lastSuccessfulUpdate = DateTime.now();
        });

        // Force table widget update
        _updateTableWidget();

        // Show confirmation message
        _showActionConfirmationMessage(action, amount);
      } else {
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Action failed'),
            backgroundColor: Colors.red,
          ),
        );

        // Force a state refresh to ensure consistency
        _forceStateRefresh(userModel.authToken!);
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

      // Force a state refresh to ensure consistency
      if (userModel.authToken != null) {
        _forceStateRefresh(userModel.authToken!);
      }
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