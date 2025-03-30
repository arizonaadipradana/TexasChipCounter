import 'dart:math' as Math;
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/poker_game_model.dart';
import 'poker_table_components.dart';

/// Dialogs used in the poker table UI
class PokerTableDialogs {
  /// Show game history dialog
  static void showHistoryDialog(BuildContext context, PokerGameModel gameModel,
      ScrollController scrollController, String currentUserId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hand History'),
          content: Container(
            width: double.maxFinite,
            height: 300,
            child: Column(
              children: [
                // Round filter buttons
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildRoundFilterChip('All'),
                      _buildRoundFilterChip('Pre-Flop'),
                      _buildRoundFilterChip('Flop'),
                      _buildRoundFilterChip('Turn'),
                      _buildRoundFilterChip('River'),
                      _buildRoundFilterChip('Showdown'),
                    ],
                  ),
                ),
                Divider(),
                // History list
                Expanded(
                  child: gameModel.actionHistory.isEmpty
                      ? Center(
                    child: Text(
                      'No actions yet',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.grey,
                      ),
                    ),
                  )
                      : ListView.builder(
                    controller: scrollController,
                    itemCount: gameModel.actionHistory.length,
                    itemBuilder: (context, index) {
                      final action = gameModel.actionHistory[index];
                      final username = action['player'] ?? 'Dealer';
                      final actionText = action['action'];
                      final amount = action['amount'];
                      final round = action['round'];
                      final isCurrentUser = username == gameModel.players
                          .firstWhere(
                              (p) => p.userId == currentUserId,
                          orElse: () =>
                              PokerPlayer(
                                  userId: '',
                                  username: '',
                                  chipBalance: 0
                              )
                      )
                          .username;

                      String displayText = '$username $actionText';
                      if (amount != null) {
                        displayText += ' $amount';
                      }

                      return Container(
                        color: index % 2 == 0 ? Colors.grey.shade100 : null,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: PokerTableComponents.getActionColor(actionText),
                            radius: 14,
                            child: Icon(
                              action['player'] == null
                                  ? Icons.casino
                                  : Icons.person,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          title: Text(
                            displayText,
                            style: TextStyle(
                              fontWeight: isCurrentUser
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            round,
                            style: TextStyle(
                              fontSize: 12,
                            ),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                        ),
                      );
                    },
                  ),
                ),
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

  /// Helper method to build round filter chips
  static Widget _buildRoundFilterChip(String roundName) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: FilterChip(
        label: Text(roundName),
        // Implement filtering logic if needed
        onSelected: (selected) {
          // For now, just a visual element without filtering
        },
        backgroundColor: Colors.grey.shade200,
        selectedColor: Colors.blue.shade100,
      ),
    );
  }

  /// Show raise dialog
  static void showRaiseDialog(BuildContext context, PokerGameModel gameModel,
      Function(String, {int? amount}) onAction) {
    final TextEditingController raiseController = TextEditingController();
    final player = gameModel.currentPlayer;

    // For a new bet, use the big blind as minimum
    final bigBlind = gameModel.gameModel.bigBlind;
    final minAmount = gameModel.currentBet > 0
        ? gameModel.minimumRaiseAmount()
        : bigBlind;

    final maxRaise = player.chipBalance;

    // Set initial value to minimum amount
    raiseController.text = minAmount.toString();

    // Flag to track validation errors
    bool hasError = false;
    String errorMessage = '';

    // Make sure we have a valid context before showing dialog
    final BuildContext contextToUse = navigatorKey.currentContext ?? context;

    showDialog(
      context: contextToUse,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Validate the current input
            void validateAmount() {
              final amount = int.tryParse(raiseController.text);

              if (amount == null) {
                setState(() {
                  hasError = true;
                  errorMessage = 'Please enter a valid number';
                });
              } else if (amount < minAmount) {
                setState(() {
                  hasError = true;
                  errorMessage = gameModel.currentBet > 0
                      ? 'Raise must be at least $minAmount chips'
                      : 'Bet must be at least ${bigBlind} chips (the big blind)';
                });
              } else if (amount > maxRaise) {
                setState(() {
                  hasError = true;
                  errorMessage = 'You only have $maxRaise chips';
                });
              } else {
                setState(() {
                  hasError = false;
                  errorMessage = '';
                });
              }
            }

            return AlertDialog(
              title: Text(gameModel.currentBet > 0
                  ? 'Raise Amount'
                  : 'Bet Amount'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: raiseController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Amount (chips)',
                      hintText: 'Min: $minAmount, Max: $maxRaise',
                      border: const OutlineInputBorder(),
                      errorText: hasError ? errorMessage : null,
                    ),
                    onChanged: (value) {
                      validateAmount();
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    gameModel.currentBet > 0
                        ? 'Minimum raise: $minAmount chips'
                        : 'Minimum bet: $bigBlind chips (big blind)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Your chips: $maxRaise'),
                  const SizedBox(height: 16),
                  Slider(
                    min: minAmount.toDouble(),
                    max: maxRaise.toDouble(),
                    divisions: maxRaise - minAmount > 100
                        ? 100
                        : Math.max(1, maxRaise - minAmount),
                    value: Math.min(
                      Math.max(
                        double.tryParse(raiseController.text) ??
                            minAmount.toDouble(),
                        minAmount.toDouble(),
                      ),
                      maxRaise.toDouble(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        raiseController.text = value.toInt().toString();
                        validateAmount();
                      });
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _quickAmountButton(raiseController, minAmount, () {
                        setState(() {
                          validateAmount();
                        });
                      }),
                      _quickAmountButton(
                          raiseController, (maxRaise / 3).ceil(), () {
                        setState(() {
                          validateAmount();
                        });
                      }),
                      _quickAmountButton(
                          raiseController, (maxRaise / 2).ceil(), () {
                        setState(() {
                          validateAmount();
                        });
                      }),
                      _quickAmountButton(raiseController, maxRaise, () {
                        setState(() {
                          validateAmount();
                        });
                      }),
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
                  onPressed: hasError ? null : () {
                    final amount = int.tryParse(raiseController.text);
                    if (amount != null && amount >= minAmount &&
                        amount <= maxRaise) {
                      Navigator.of(context).pop();
                      onAction(
                        gameModel.currentBet > 0 ? 'raise' : 'bet',
                        amount: amount,
                      );
                    } else {
                      // Validate one more time
                      validateAmount();
                    }
                  },
                  child: Text(
                      gameModel.currentBet > 0 ? 'Raise' : 'Bet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Quick button to set specific amount with validation callback
  static Widget _quickAmountButton(TextEditingController controller, int amount,
      [Function? onChanged]) {
    return ElevatedButton(
      onPressed: () {
        controller.text = amount.toString();
        if (onChanged != null) {
          onChanged();
        }
      },
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text('$amount'),
    );
  }

  /// Show game rules dialog
  static void showRulesDialog(BuildContext context) {
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

  /// Show connection status dialog
  static void showConnectionStatus(BuildContext context, bool isConnected,
      int errorCount, DateTime? lastUpdate, String gameId) {
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
              _statusRow('Game ID', gameId, Colors.blue),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  /// Helper to create status row
  static Widget _statusRow(String label, String value, Color color) {
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

  /// Confirm exit game dialog
  static Future<bool> confirmExitGame(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Exit Game?'),
          content: const Text('Are you sure you want to exit this poker game?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Exit Game'),
            ),
          ],
        );
      },
    ) ?? false;
  }

  /// Show insufficient chips dialog
  static void showInsufficientChipsDialog(BuildContext context) {
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
}