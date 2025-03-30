import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game_model.dart';
import '../models/poker_game_model.dart';
import '../models/user_model.dart';
import '../services/game_service_core.dart';
import '../widgets/poker_table_widget.dart';
import 'poker_game_handlers.dart';
import 'poker_game_state.dart';
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

  // Reference to state and handlers
  late PokerGameState _gameState;
  late PokerGameHandlers _handlers;

  @override
  void initState() {
    super.initState();
    _pokerGame = PokerGameModel(gameModel: widget.game);

    // Initialize state and handlers
    _gameState = PokerGameState();
    _handlers = PokerGameHandlers(
        updateUI: _updateUI,
        showTurnChangeNotification: _showTurnChangeNotification,
        showActionSnackBar: _showActionSnackBar,
        setHandStarted: (value) {
          setState(() {
            _handStarted = value;
          });
        }
    );

    // Register for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);

    // Initialize game service after the first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGameService();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _handlers.handleAppLifecycleChange(state, _gameService,
        widget.game.id, _isExiting, context);
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
      _gameService!.listenForAllGameUpdates(widget.game.id,
              (data) => _handlers.handleGameUpdate(data, _pokerGame, context));

      // Setup UI update timer and forced refresh timer
      _gameState.setupUiUpdateTimer(() => _updateUI());
      _gameState.setupForcedRefreshTimer(userModel.authToken!,
              (token) => _forceStateRefresh(token));

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

  void _forceStateRefresh(String authToken) async {
    if (_gameState.forcedRefreshInProgress) return;

    _gameState.forcedRefreshInProgress = true;

    try {
      print('Forcing state refresh for game: ${widget.game.id}');

      if (_gameService == null) {
        _gameState.forcedRefreshInProgress = false;
        return;
      }

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
          _gameState.consecutiveErrors = 0;
          _gameState.lastSuccessfulUpdate = DateTime.now();
        });

        // If player index changed, update UI and show notification
        if (oldPlayerIndex != newPlayerIndex) {
          _gameState.lastKnownPlayerIndex = newPlayerIndex;

          _updateUI();

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
        _gameState.consecutiveErrors++;
        print('Failed to refresh state: ${result['message'] ?? 'Unknown error'}');

        // If too many consecutive errors, force reconnection
        if (_gameState.consecutiveErrors >= 3 && _gameService != null) {
          _gameService!.forceStateSynchronization(widget.game.id, authToken);
          _gameState.consecutiveErrors = 0;
        }
      }
    } catch (e) {
      _gameState.consecutiveErrors++;
      print('Error in forced refresh: $e');
    } finally {
      _gameState.forcedRefreshInProgress = false;
    }
  }

  void _updateUI() {
    if (mounted) {
      setState(() {});

      // Force the game model to notify listeners
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
  }

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

    // Clean up state resources
    _gameState.dispose();

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
                _handlers.showRulesDialog(context);
              } else if (value == 'exit') {
                _handlers.confirmExitGame(context, () {
                  _isExiting = true;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const HomeScreen()),
                        (route) => false,
                  );
                });
              } else if (value == 'status') {
                _handlers.showConnectionStatus(context,
                    _gameService, _gameState, widget.game.id);
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
              onAction: (action, {amount}) => _handlers.handleAction(
                  action, pokerGame, userModel, _gameService,
                  widget.game.id, context, amount: amount),
              onStartNewHand: userModel.id == widget.game.hostId
                  ? () => _handlers.startNewHand(_pokerGame, _gameService, widget.game.id)
                  : () {},
              gameId: widget.game.id,
              gameService: _gameService,
            );
          },
        ),
      ),
    );
  }
}