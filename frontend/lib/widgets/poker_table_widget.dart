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

class _PokerTableWidgetState extends State<PokerTableWidget> {
  int _lastPlayerIndex = -1;
  String? _lastAction;
  final ScrollController _historyScrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    // Scroll to the bottom of history list whenever it's opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToHistoryEnd();
    });
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

    // Check if the player turn has changed
    if (_lastPlayerIndex != widget.gameModel.currentPlayerIndex &&
        widget.gameModel.handInProgress) {
      _lastPlayerIndex = widget.gameModel.currentPlayerIndex;

      // If turn has changed, ensure UI updates
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // This is crucial - force a UI update whenever the current player changes
        _updateUI();
      });
    }

    // Also check if any player data has changed
    bool playerDataChanged = false;

    if (oldWidget.gameModel.players.length == widget.gameModel.players.length) {
      for (int i = 0; i < oldWidget.gameModel.players.length; i++) {
        final oldPlayer = oldWidget.gameModel.players[i];
        final newPlayer = widget.gameModel.players[i];

        // Check for changes in chip balance, current bet, or folded status
        if (oldPlayer.chipBalance != newPlayer.chipBalance ||
            oldPlayer.currentBet != newPlayer.currentBet ||
            oldPlayer.hasFolded != newPlayer.hasFolded) {
          playerDataChanged = true;
          break;
        }
      }
    } else {
      // Player count changed
      playerDataChanged = true;
    }

    // If player data changed, update UI
    if (playerDataChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateUI();
      });
    }

    // If pot amount changed, update UI
    if (oldWidget.gameModel.pot != widget.gameModel.pot) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateUI();
      });
    }

    // If history has changed, scroll to the bottom
    if (oldWidget.gameModel.actionHistory.length !=
        widget.gameModel.actionHistory.length) {
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
            }
          },
        );
      },
    );
  }

  void _updateUI() {
    if (mounted) {
      setState(() {});

      // Force the game model to notify listeners
      widget.gameModel.notifyListeners();

      // Add a subtle animation effect to highlight the change
      _animateTableChange();
    }
  }

  void _animateTableChange() {
    // We'll use a very subtle animation just to draw attention to the fact
    // that the state has changed - implemented in the widget tree with
    // AnimatedContainer
  }

  void updateTable() {
    _updateUI();
  }

  @override
  void dispose() {
    _historyScrollController.dispose();
    super.dispose();
  }
}