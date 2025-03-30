import 'dart:math' as Math;
import 'package:flutter/material.dart';

import '../models/game_model.dart';
import '../models/poker_game_model.dart';
import 'card_widget.dart';
import 'poker_table_dialogs.dart';
import '../models/card_model.dart' as poker;

/// Reusable components for the poker table UI
class PokerTableComponents {
  /// Build a player card component
  static Widget buildPlayerCard(PokerPlayer player, bool isCurrentPlayer, bool isCurrentUser) {
    final isDealerButton = player.userId == player.userId; // This is a placeholder, needs specific logic
    final isSmallBlind = false; // This is a placeholder, needs specific logic
    final isBigBlind = false; // This is a placeholder, needs specific logic

    // Calculate animation values for visual cues
    final Color backgroundColor = isCurrentPlayer
        ? Colors.blue.withOpacity(0.9)
        : Colors.black.withOpacity(0.7);

    final Color borderColor = isCurrentUser
        ? Colors.yellow
        : isCurrentPlayer
        ? Colors.green
        : Colors.white;

    final double borderWidth = isCurrentUser
        ? 3
        : isCurrentPlayer
        ? 2
        : 1;

    return Container(
      width: 160,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
        boxShadow: isCurrentPlayer ? [
          BoxShadow(
            color: Colors.green.withOpacity(0.6),
            blurRadius: 10,
            spreadRadius: 3,
          )
        ] : null,
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Player name with turn indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isCurrentPlayer)
                Icon(Icons.arrow_right, color: Colors.white, size: 20),
              Flexible(
                child: Text(
                  player.username,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: isCurrentUser ? 16 : 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isCurrentPlayer)
                Icon(Icons.arrow_left, color: Colors.white, size: 20),
            ],
          ),

          // Chip balance
          Text(
            '${player.chipBalance} chips',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),

          const SizedBox(height: 4),

          // Player status badges
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDealerButton)
                _buildStatusBadge(
                  'D',
                  Colors.white,
                  Colors.black,
                ),
              if (isSmallBlind)
                _buildStatusBadge(
                  'SB',
                  Colors.blue.shade300,
                  Colors.black,
                ),
              if (isBigBlind)
                _buildStatusBadge(
                  'BB',
                  Colors.orange.shade300,
                  Colors.black,
                ),
              if (player.hasFolded)
                _buildStatusBadge(
                  'Fold',
                  Colors.red,
                  Colors.white,
                ),
              if (player.isAllIn)
                _buildStatusBadge(
                  'All-In',
                  Colors.purple,
                  Colors.white,
                ),
              if (isCurrentPlayer)
                _buildStatusBadge(
                  'TURN',
                  Colors.green,
                  Colors.white,
                ),
            ],
          ),

          const SizedBox(height: 8),

          // Player's current bet with animation for changes
          if (player.currentBet > 0)
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.8, end: 1.0),
              duration: Duration(milliseconds: 500),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        )
                      ],
                    ),
                    child: Text(
                      'Bet: ${player.currentBet}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),

          const SizedBox(height: 8),

          // Player's hole cards
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Card content can be added here
            ],
          ),

          // Hand evaluation at showdown
          if (player.handEvaluation != null)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.7),
                    blurRadius: 8,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: Text(
                player.handEvaluation!.displayName,
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Build a status badge for player card
  static Widget _buildStatusBadge(String text, Color color, Color textColor) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  /// Build the community cards display
  static Widget buildCommunityCards(List<poker.Card> cards, bool handInProgress, String currentRoundName) {
    final placeholders = 5 - cards.length;

    return AnimatedContainer(
      duration: Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            spreadRadius: 2,
          )
        ],
      ),
      padding: EdgeInsets.all(8),
      child: Column(
        children: [
          // Betting round indicator
          if (handInProgress)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              margin: EdgeInsets.only(bottom: 8),
              child: Text(
                currentRoundName,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

          // Cards
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...cards.map(
                    (card) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: PlayingCardWidget(
                    card: card,
                    height: 100,
                    width: 70,
                  ),
                ),
              ),
              ...List.generate(
                placeholders,
                    (index) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: PlayingCardWidget(
                    card: null,
                    height: 100,
                    width: 70,
                    faceDown: false,
                    showShadow: false,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build the pot display
  static Widget buildPotDisplay(int pot) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.9, end: 1.0),
      duration: Duration(milliseconds: 500),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Pot: $pot chips',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Build the game state info widget
  static Widget buildGameInfo(PokerGameModel gameModel, String currentUserId) {
    String stateText = 'Waiting for players...';

    if (gameModel.handInProgress) {
      if (gameModel.currentRound == BettingRound.showdown) {
        if (gameModel.winners.isNotEmpty) {
          if (gameModel.winners.length == 1) {
            stateText = '${gameModel.winners[0].username} wins!';
          } else {
            final names = gameModel.winners.map((p) => p.username).join(', ');
            stateText = 'Split pot! Winners: $names';
          }
        } else {
          stateText = 'Showdown!';
        }
      } else {
        // Make sure we have a current player before trying to access username
        if (gameModel.players.isNotEmpty &&
            gameModel.currentPlayerIndex < gameModel.players.length) {
          final currentPlayerId = gameModel.currentPlayer.userId;
          final isCurrentUserTurn = currentPlayerId == currentUserId;

          stateText = isCurrentUserTurn
              ? 'YOUR TURN!'
              : '${gameModel.currentRoundName} - ${gameModel.currentPlayer.username}\'s turn';
        } else {
          stateText = gameModel.currentRoundName;
        }
      }
    } else if (gameModel.gameModel.status == GameStatus.active) {
      // Game is active but hand not in progress
      stateText = 'Starting game...';
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        stateText,
        style: TextStyle(
          color: stateText.contains('YOUR TURN') ? Colors.yellow : Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  /// Position players around the table
  static List<Widget> positionPlayers(double maxWidth, double maxHeight,
      PokerGameModel gameModel, String currentUserId) {
    final players = gameModel.players;
    final positions = _calculatePlayerPositions(
      players.length,
      maxWidth,
      maxHeight,
    );

    return List.generate(players.length, (index) {
      final player = players[index];
      final position = positions[index];
      final isCurrentPlayer =
          gameModel.handInProgress && index == gameModel.currentPlayerIndex;
      final isCurrentUser = player.userId == currentUserId;

      // Add a pulsing animation for current player
      Widget playerWidget = buildPlayerCard(player, isCurrentPlayer, isCurrentUser);

      if (isCurrentPlayer) {
        // Wrap in animated container for current player
        playerWidget = TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.95, end: 1.05),
          duration: Duration(milliseconds: 1000),
          curve: Curves.easeInOut,
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: child,
            );
          },
          child: playerWidget,
        );
      }

      return Positioned(
        left: position['left'],
        top: position['top'],
        child: playerWidget,
      );
    });
  }

  /// Calculate positions for players around the table
  static List<Map<String, double>> _calculatePlayerPositions(int playerCount,
      double maxWidth, double maxHeight) {
    final List<Map<String, double>> positions = [];
    final centerX = maxWidth / 2;
    final centerY = maxHeight / 2;
    final tableWidth = maxWidth * 0.8;
    final tableHeight = maxHeight * 0.6;
    final radius = Math.min(tableWidth, tableHeight) / 2 + 40;

    // Special case for 2 players (heads-up)
    if (playerCount == 2) {
      // Position for current user
      positions.add({
        'left': centerX - 80,
        'top': centerY + radius * 0.8,
      });

      // Position for opponent
      positions.add({
        'left': centerX - 80,
        'top': centerY - radius * 0.8 - 100,
      });
      return positions;
    }

    // Calculate positions for more than 2 players
    for (int i = 0; i < playerCount; i++) {
      // Calculate angle (in radians) for this position
      final angle = (2 * Math.pi * i / playerCount) - Math.pi / 2;

      // Calculate position based on angle and radius
      final left = centerX + radius * Math.cos(angle) - 80;
      final top = centerY + radius * Math.sin(angle) - 50;

      positions.add({
        'left': left,
        'top': top,
      });
    }

    return positions;
  }

  /// Build action buttons
  static Widget buildActionButtons(BuildContext context, PokerGameModel gameModel,
      Function(String, {int? amount}) onAction) {
    final player = gameModel.currentPlayer;
    final canCheck = gameModel.canCheck();
    final callAmount = gameModel.callAmount();
    final minRaise = gameModel.minimumRaiseAmount();
    final bool canRaise = player.chipBalance >= minRaise;

    // Current big blind value for minimum bet
    final bigBlind = gameModel.gameModel.bigBlind;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.blue.shade700,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            spreadRadius: 3,
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Minimum bet/raise info
          if (gameModel.currentBet > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                'Min raise: $minRaise chips',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                'Min bet: $bigBlind chips',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Fold button
              ElevatedButton(
                onPressed: () => onAction('fold'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 5,
                ),
                child: Row(
                  children: [
                    Icon(Icons.close),
                    SizedBox(width: 4),
                    const Text('Fold'),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Check or Call button
              ElevatedButton(
                onPressed: canCheck
                    ? () => onAction('check')
                    : callAmount > 0
                    ? () => onAction('call')
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canCheck ? Colors.green : Colors.blue,
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 5,
                ),
                child: Row(
                  children: [
                    Icon(canCheck ? Icons.check : Icons.call),
                    SizedBox(width: 4),
                    Text(canCheck
                        ? 'Check'
                        : callAmount > 0
                        ? 'Call $callAmount'
                        : 'Call'),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Raise button
              ElevatedButton(
                onPressed: canRaise
                    ? () => PokerTableDialogs.showRaiseDialog(
                    context, gameModel, onAction)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 5,
                ),
                child: Row(
                  children: [
                    Icon(Icons.arrow_upward),
                    SizedBox(width: 4),
                    Text(gameModel.currentBet > 0 ? 'Raise' : 'Bet'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Helper function to get color for different action types
  static Color getActionColor(String action) {
    if (action.contains('fold')) {
      return Colors.red;
    } else if (action.contains('check')) {
      return Colors.green;
    } else if (action.contains('call')) {
      return Colors.blue;
    } else if (action.contains('raise') || action.contains('bet')) {
      return Colors.amber;
    } else if (action.contains('win')) {
      return Colors.purple;
    } else if (action.contains('deal')) {
      return Colors.teal;
    } else {
      return Colors.grey;
    }
  }
}