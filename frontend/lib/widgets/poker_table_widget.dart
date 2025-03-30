import 'dart:async';
import 'dart:math' as Math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/game_model.dart';
import '../models/poker_game_model.dart';
import '../models/user_model.dart';
import '../services/game_service_core.dart';
import 'card_widget.dart';
import 'poker_table_components.dart';
import 'poker_table_dialogs.dart';
import 'poker_table_layout.dart';

class PokerTableWidget extends StatefulWidget {
  final PokerGameModel gameModel;
  final String currentUserId;
  final Function(String, {int? amount}) onAction;
  final VoidCallback onStartNewHand;
  final GameService? gameService;
  final String gameId;

  const PokerTableWidget({
    Key? key,
    required this.gameModel,
    required this.currentUserId,
    required this.onAction,
    required this.onStartNewHand,
    this.gameService,
    required this.gameId,
  }) : super(key: key);

  @override
  State<PokerTableWidget> createState() => _PokerTableWidgetState();
}

class _PokerTableWidgetState extends State<PokerTableWidget> with WidgetsBindingObserver {
  int _lastPlayerIndex = -1;
  int _lastPot = 0;
  final Set<String> _processedActionIds = {};
  final ScrollController _historyScrollController = ScrollController();

  // Add a timer to force UI updates periodically
  Timer? _uiRefreshTimer;
  DateTime _lastManualRefresh = DateTime.now();

  @override
  void initState() {
    super.initState();

    // Register as an observer to handle app lifecycle changes
    WidgetsBinding.instance.addObserver(this);

    // Initialize last known values
    _lastPlayerIndex = widget.gameModel.currentPlayerIndex;
    _lastPot = widget.gameModel.pot;

    // Scroll to the bottom of history list whenever it's opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToHistoryEnd();

      // Start a periodic UI refresh timer to ensure UI stays updated
      _startUiRefreshTimer();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // When app comes back to foreground, force refresh
      _updateUI();

      // Also request a state refresh from the server
      _requestServerRefresh();
    }
  }

  void _startUiRefreshTimer() {
    _uiRefreshTimer?.cancel();
    _uiRefreshTimer = Timer.periodic(Duration(milliseconds: 1000), (timer) {
      if (mounted) {
        // Check if it's been at least 5 seconds since last manual refresh
        final now = DateTime.now();
        if (now.difference(_lastManualRefresh).inSeconds >= 5) {
          _updateUI();
          _lastManualRefresh = now;
        }
      }
    });
  }

  void _requestServerRefresh() {
    final userModel = Provider.of<UserModel>(context, listen: false);
    if (widget.gameService != null && userModel.authToken != null) {
      widget.gameService!.forceStateSynchronization(widget.gameId, userModel.authToken!);
    }
  }

  void _scrollToHistoryEnd() {
    if (_historyScrollController.hasClients) {
      _historyScrollController.animateTo(
        _historyScrollController.position.maxScrollExtent,
        duration: Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void didUpdateWidget(PokerTableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    bool shouldUpdate = false;

    // Check if the player turn has changed
    if (_lastPlayerIndex != widget.gameModel.currentPlayerIndex) {
      _lastPlayerIndex = widget.gameModel.currentPlayerIndex;
      shouldUpdate = true;
      print('Player index changed to ${widget.gameModel.currentPlayerIndex}, updating UI');
    }

    // Check if pot has changed
    if (_lastPot != widget.gameModel.pot) {
      _lastPot = widget.gameModel.pot;
      shouldUpdate = true;
      print('Pot changed to ${widget.gameModel.pot}, updating UI');
    }

    // Check game status
    if (oldWidget.gameModel.gameModel.status != widget.gameModel.gameModel.status) {
      shouldUpdate = true;
      print('Game status changed to ${widget.gameModel.gameModel.status}, updating UI');
    }

    // Compare other important state changes
    if (oldWidget.gameModel.handInProgress != widget.gameModel.handInProgress) {
      shouldUpdate = true;
      print('Hand in progress changed to ${widget.gameModel.handInProgress}, updating UI');
    }

    // Also check if any player data has changed
    if (oldWidget.gameModel.players.length == widget.gameModel.players.length) {
      for (int i = 0; i < oldWidget.gameModel.players.length; i++) {
        final oldPlayer = oldWidget.gameModel.players[i];
        final newPlayer = widget.gameModel.players[i];

        // Check for changes in chip balance, current bet, or folded status
        if (oldPlayer.chipBalance != newPlayer.chipBalance ||
            oldPlayer.currentBet != newPlayer.currentBet ||
            oldPlayer.hasFolded != newPlayer.hasFolded ||
            oldPlayer.isAllIn != newPlayer.isAllIn) {
          shouldUpdate = true;
          print('Player ${newPlayer.username} data changed, updating UI');
          break;
        }
      }
    } else {
      // Player count changed
      shouldUpdate = true;
      print('Player count changed, updating UI');
    }

    // If any important state changed, update UI
    if (shouldUpdate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateUI();
        _lastManualRefresh = DateTime.now();
      });
    }

    // If history has changed, scroll to the bottom
    if (oldWidget.gameModel.actionHistory.length != widget.gameModel.actionHistory.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToHistoryEnd();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final tableWidth = maxWidth * 0.8;
        final tableHeight = maxHeight * 0.6;

        return PokerTableLayout(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          tableWidth: tableWidth,
          tableHeight: tableHeight,
          gameModel: widget.gameModel,
          currentUserId: widget.currentUserId,
          onAction: widget.onAction,
          onStartNewHand: widget.onStartNewHand,
          historyScrollController: _historyScrollController,
          gameId: widget.gameId,
          gameService: widget.gameService,
          onHistoryDialog: () => PokerTableDialogs.showHistoryDialog(
              context,
              widget.gameModel,
              _historyScrollController,
              widget.currentUserId
          ),
          onSyncPressed: () {
            final userModel = Provider.of<UserModel>(context, listen: false);
            if (userModel.authToken != null && widget.gameService != null) {
              widget.gameService?.resyncGameState(widget.gameId, userModel.authToken!);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Syncing game state...'),
                  duration: Duration(seconds: 1),
                ),
              );

              // Immediately update UI
              _updateUI();
              _lastManualRefresh = DateTime.now();
            }
          },
        );
      },
    );
  }

  void _updateUI() {
    if (mounted) {
      setState(() {
        // Explicitly update local tracking variables
        _lastPlayerIndex = widget.gameModel.currentPlayerIndex;
        _lastPot = widget.gameModel.pot;
      });

      // Force the game model to notify listeners
      widget.gameModel.notifyListeners();

      // Log UI update for debugging
      print('UI updated at ${DateTime.now().toIso8601String()} - Player Index: $_lastPlayerIndex, Pot: $_lastPot');
    }
  }

  // Public method that can be called from outside
  void updateTable() {
    _updateUI();
    _lastManualRefresh = DateTime.now();
  }

  @override
  void dispose() {
    // Clean up resources
    WidgetsBinding.instance.removeObserver(this);
    _uiRefreshTimer?.cancel();
    _historyScrollController.dispose();
    _processedActionIds.clear();
    super.dispose();
  }
}