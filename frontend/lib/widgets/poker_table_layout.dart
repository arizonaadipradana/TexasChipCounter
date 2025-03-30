import 'dart:math' as Math;
import 'package:flutter/material.dart';
import '../models/poker_game_model.dart';
import '../services/game_service_core.dart';
import 'poker_table_components.dart';
import '../models/card_model.dart' as poker;

/// Main layout component for the poker table
class PokerTableLayout extends StatelessWidget {
  final double maxWidth;
  final double maxHeight;
  final double tableWidth;
  final double tableHeight;
  final PokerGameModel gameModel;
  final String currentUserId;
  final Function(String, {int? amount}) onAction;
  final VoidCallback onStartNewHand;
  final ScrollController historyScrollController;
  final String gameId;
  final GameService? gameService;
  final VoidCallback onHistoryDialog;
  final VoidCallback onSyncPressed;

  const PokerTableLayout({
    Key? key,
    required this.maxWidth,
    required this.maxHeight,
    required this.tableWidth,
    required this.tableHeight,
    required this.gameModel,
    required this.currentUserId,
    required this.onAction,
    required this.onStartNewHand,
    required this.historyScrollController,
    required this.gameId,
    this.gameService,
    required this.onHistoryDialog,
    required this.onSyncPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background
        Container(
          width: maxWidth,
          height: maxHeight,
          color: Colors.green.shade800,
        ),

        // Table
        Center(
          child: Container(
            width: tableWidth,
            height: tableHeight,
            decoration: BoxDecoration(
              color: Colors.green.shade600,
              borderRadius: BorderRadius.circular(tableWidth / 2),
              border: Border.all(
                color: Colors.brown.shade800,
                width: 8,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pot amount
                  PokerTableComponents.buildPotDisplay(gameModel.pot),

                  const SizedBox(height: 12),

                  // Community cards
                  PokerTableComponents.buildCommunityCards(
                      gameModel.communityCards as List<poker.Card>,
                      gameModel.handInProgress,
                      gameModel.currentRoundName
                  ),
                  const SizedBox(height: 12),

                  // Game state info
                  PokerTableComponents.buildGameInfo(gameModel, currentUserId),
                ],
              ),
            ),
          ),
        ),

        // Players around the table
        ...PokerTableComponents.positionPlayers(maxWidth, maxHeight, gameModel, currentUserId),

        // Action buttons
        if (gameModel.handInProgress &&
            gameModel.players.isNotEmpty &&
            gameModel.currentPlayerIndex < gameModel.players.length &&
            gameModel.currentPlayer.userId == currentUserId &&
            gameModel.currentRound != BettingRound.showdown)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: PokerTableComponents.buildActionButtons(
              context,
              gameModel,
              onAction,
            ),
          ),

        // Sync button
        Positioned(
          top: 8,
          left: 8,
          child: IconButton(
            icon: const Icon(
              Icons.sync,
              color: Colors.white,
            ),
            onPressed: onSyncPressed,
            tooltip: 'Sync game state',
          ),
        ),

        // Start new hand button
        if (!gameModel.handInProgress)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton(
                onPressed: onStartNewHand,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
                child: const Text(
                  'Start New Hand',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),

        // Game history button
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            icon: const Icon(
              Icons.history,
              color: Colors.white,
            ),
            onPressed: onHistoryDialog,
          ),
        ),
      ],
    );
  }
}