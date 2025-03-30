import 'dart:math' as Math;
import 'package:flutter/material.dart';
import '../models/card_model.dart' as poker;
import '../models/poker_game_model.dart';
import 'card_widget.dart';

class PokerTableWidget extends StatelessWidget {
  final PokerGameModel gameModel;
  final String currentUserId;
  final Function(String, {int? amount}) onAction;
  final VoidCallback onStartNewHand;

  const PokerTableWidget({
    Key? key,
    required this.gameModel,
    required this.currentUserId,
    required this.onAction,
    required this.onStartNewHand,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final tableWidth = maxWidth * 0.8;
        final tableHeight = maxHeight * 0.6;

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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Pot: ${gameModel.pot} chips',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Community cards
                      _buildCommunityCards(),

                      const SizedBox(height: 12),

                      // Game state info
                      _buildGameInfo(),
                    ],
                  ),
                ),
              ),
            ),

            // Players around the table
            ..._positionPlayers(maxWidth, maxHeight),

            // Action buttons
            if (gameModel.handInProgress &&
                gameModel.currentPlayer.userId == currentUserId &&
                gameModel.currentRound != BettingRound.showdown)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: _buildActionButtons(),
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

            // Game history
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(
                  Icons.history,
                  color: Colors.white,
                ),
                onPressed: () {
                  _showHistoryDialog(context);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // Build the community cards display
  Widget _buildCommunityCards() {
    final cards = gameModel.communityCards;
    final placeholders = 5 - cards.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...cards.map(
              (card) => PlayingCardWidget(
            card: card,
            height: 100,
            width: 70,
          ),
        ),
        ...List.generate(
          placeholders,
              (index) => PlayingCardWidget(
            card: null,
            height: 100,
            width: 70,
            faceDown: false,
            showShadow: false,
          ),
        ),
      ],
    );
  }

  // Build the game state info widget
  Widget _buildGameInfo() {
    String stateText = 'Waiting for players...';

    if (gameModel.handInProgress) {
      if (gameModel.currentRound == BettingRound.showdown) {
        if (gameModel.winners.isNotEmpty) {
          if (gameModel.winners.length == 1) {
            stateText =
            '${gameModel.winners[0].username} wins!';
          } else {
            final names = gameModel.winners.map((p) => p.username).join(', ');
            stateText = 'Split pot! Winners: $names';
          }
        } else {
          stateText = 'Showdown!';
        }
      } else {
        stateText =
        '${gameModel.currentRoundName} - ${gameModel.currentPlayer.username}\'s turn';
      }
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
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  // Position players around the table
  List<Widget> _positionPlayers(double maxWidth, double maxHeight) {
    final players = gameModel.players;
    final positions = _calculatePlayerPositions(
      players.length,
      maxWidth,
      maxHeight,
    );

    return List.generate(players.length, (index) {
      final player = players[index];
      final position = positions[index];
      final isCurrentUser = player.userId == currentUserId;
      final isCurrentPlayer =
          gameModel.handInProgress && index == gameModel.currentPlayerIndex;
      final isDealerButton = index == gameModel.dealerPosition;
      final isSmallBlind = index == gameModel.smallBlindPosition;
      final isBigBlind = index == gameModel.bigBlindPosition;

      return Positioned(
        left: position['left'],
        top: position['top'],
        child: Container(
          width: 160,
          decoration: BoxDecoration(
            color: isCurrentPlayer
                ? Colors.blue.withOpacity(0.8)
                : Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCurrentUser ? Colors.yellow : Colors.white,
              width: isCurrentUser ? 3 : 1,
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Player name and chips
              Text(
                player.username,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: isCurrentUser ? 16 : 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
                ],
              ),

              const SizedBox(height: 8),

              // Player's current bet
              if (player.currentBet > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Bet: ${player.currentBet}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

              const SizedBox(height: 8),

              // Player's hole cards
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // First card
                  if (player.holeCards.isNotEmpty)
                    PlayingCardWidget(
                      card: isCurrentUser || gameModel.currentRound == BettingRound.showdown && !player.hasFolded
                          ? player.holeCards[0]
                          : null,
                      faceDown: !isCurrentUser && gameModel.currentRound != BettingRound.showdown,
                      height: 70,
                      width: 50,
                    ),
                  // Second card
                  if (player.holeCards.length > 1)
                    PlayingCardWidget(
                      card: isCurrentUser || gameModel.currentRound == BettingRound.showdown && !player.hasFolded
                          ? player.holeCards[1]
                          : null,
                      faceDown: !isCurrentUser && gameModel.currentRound != BettingRound.showdown,
                      height: 70,
                      width: 50,
                    ),
                ],
              ),

              // Player's hand evaluation at showdown
              if (gameModel.currentRound == BettingRound.showdown &&
                  !player.hasFolded &&
                  player.handEvaluation != null)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: gameModel.winners.contains(player)
                        ? Colors.amber
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    player.handEvaluation!.displayName,
                    style: TextStyle(
                      color: gameModel.winners.contains(player)
                          ? Colors.black
                          : Colors.grey.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  // Calculate positions for players around the table
  List<Map<String, double>> _calculatePlayerPositions(
      int playerCount, double maxWidth, double maxHeight) {
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

  // Build a status badge
  Widget _buildStatusBadge(String text, Color color, Color textColor) {
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

  // Build action buttons
  Widget _buildActionButtons() {
    final player = gameModel.currentPlayer;
    final canCheck = gameModel.canCheck();
    final callAmount = gameModel.callAmount();
    final minRaise = gameModel.minimumRaiseAmount();
    final bool canRaise = player.chipBalance >= minRaise;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Fold button
          ElevatedButton(
            onPressed: () => onAction('fold'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Fold'),
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
            ),
            child: Text(canCheck
                ? 'Check'
                : callAmount > 0
                ? 'Call $callAmount'
                : 'Call'),
          ),

          const SizedBox(width: 8),

          // Raise button
          ElevatedButton(
            onPressed: canRaise ? () => _showRaiseDialog() : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
            ),
            child: Text(gameModel.currentBet > 0 ? 'Raise' : 'Bet'),
          ),
        ],
      ),
    );
  }

  // Show dialog to select raise amount
  void _showRaiseDialog() {
    final TextEditingController raiseController = TextEditingController();
    final player = gameModel.currentPlayer;
    final minRaise = gameModel.minimumRaiseAmount();
    final maxRaise = player.chipBalance;

    showDialog(
      context: GlobalObjectKey(gameModel).currentContext!,
      builder: (context) {
        return AlertDialog(
          title: Text(gameModel.currentBet > 0 ? 'Raise Amount' : 'Bet Amount'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: raiseController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount (chips)',
                  hintText: 'Min: $minRaise, Max: $maxRaise',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text('Min: $minRaise, Max: $maxRaise'),
              Slider(
                min: minRaise.toDouble(),
                max: maxRaise.toDouble(),
                divisions: maxRaise - minRaise > 100
                    ? 100
                    : Math.max(1, maxRaise - minRaise),
                value: double.tryParse(raiseController.text) ?? minRaise.toDouble(),
                onChanged: (value) {
                  raiseController.text = value.toInt().toString();
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _quickAmountButton(raiseController, minRaise),
                  _quickAmountButton(raiseController, (maxRaise / 3).ceil()),
                  _quickAmountButton(raiseController, (maxRaise / 2).ceil()),
                  _quickAmountButton(raiseController, maxRaise),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final raiseAmount = int.tryParse(raiseController.text);
                if (raiseAmount != null && raiseAmount >= minRaise && raiseAmount <= maxRaise) {
                  Navigator.of(context).pop();
                  onAction(
                    gameModel.currentBet > 0 ? 'raise' : 'bet',
                    amount: raiseAmount,
                  );
                }
              },
              child: Text(gameModel.currentBet > 0 ? 'Raise' : 'Bet'),
            ),
          ],
        );
      },
    );
  }

  // Quick button to set specific amount
  Widget _quickAmountButton(TextEditingController controller, int amount) {
    return ElevatedButton(
      onPressed: () {
        controller.text = amount.toString();
      },
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text('$amount'),
    );
  }

  // Show game history
  void _showHistoryDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hand History'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: gameModel.actionHistory.length,
              itemBuilder: (context, index) {
                final action = gameModel.actionHistory[index];
                final username = action['player'] ?? 'Dealer';
                final actionText = action['action'];
                final amount = action['amount'];
                final round = action['round'];

                String displayText = '$username $actionText';
                if (amount != null) {
                  displayText += ' $amount';
                }

                return ListTile(
                  leading: Icon(
                    action['player'] == null
                        ? Icons.casino
                        : Icons.person,
                    color: _getActionColor(actionText),
                  ),
                  title: Text(displayText),
                  subtitle: Text(round),
                  dense: true,
                );
              },
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

  // Get color for different action types
  Color _getActionColor(String action) {
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
    } else {
      return Colors.grey;
    }
  }
}