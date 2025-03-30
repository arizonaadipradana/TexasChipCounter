import 'dart:math' as Math;
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/game_model.dart';
import '../models/poker_game_model.dart';
import 'card_widget.dart';

class PokerTableWidget extends StatefulWidget {
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

      // If turn has changed, show a notification
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.gameModel.players.isNotEmpty &&
            widget.gameModel.currentPlayerIndex <
                widget.gameModel.players.length) {
          final playerName = widget.gameModel.players[widget.gameModel
              .currentPlayerIndex].username;

          // Only show the notification if we're not already showing one for this turn
          if (_lastAction != 'turn_${widget.gameModel.currentPlayerIndex}') {
            _lastAction = 'turn_${widget.gameModel.currentPlayerIndex}';

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('It\'s $playerName\'s turn now'),
                duration: const Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
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
                          'Pot: ${widget.gameModel.pot} chips',
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
            if (widget.gameModel.handInProgress &&
                widget.gameModel.players.isNotEmpty &&
                widget.gameModel.currentPlayerIndex <
                    widget.gameModel.players.length &&
                widget.gameModel.currentPlayer.userId == widget.currentUserId &&
                widget.gameModel.currentRound != BettingRound.showdown)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: _buildActionButtons(),
              ),

            // Start new hand button
            if (!widget.gameModel.handInProgress)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: ElevatedButton(
                    onPressed: widget.onStartNewHand,
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
    final cards = widget.gameModel.communityCards;
    final placeholders = 5 - cards.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...cards.map(
              (card) =>
              PlayingCardWidget(
                card: card,
                height: 100,
                width: 70,
              ),
        ),
        ...List.generate(
          placeholders,
              (index) =>
              PlayingCardWidget(
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

    if (widget.gameModel.handInProgress) {
      if (widget.gameModel.currentRound == BettingRound.showdown) {
        if (widget.gameModel.winners.isNotEmpty) {
          if (widget.gameModel.winners.length == 1) {
            stateText =
            '${widget.gameModel.winners[0].username} wins!';
          } else {
            final names = widget.gameModel.winners.map((p) => p.username).join(
                ', ');
            stateText = 'Split pot! Winners: $names';
          }
        } else {
          stateText = 'Showdown!';
        }
      } else {
        // Make sure we have a current player before trying to access username
        if (widget.gameModel.players.isNotEmpty &&
            widget.gameModel.currentPlayerIndex <
                widget.gameModel.players.length) {
          stateText =
          '${widget.gameModel.currentRoundName} - ${widget.gameModel
              .currentPlayer.username}\'s turn';
        } else {
          stateText = widget.gameModel.currentRoundName;
        }
      }
    } else if (widget.gameModel.gameModel.status == GameStatus.active) {
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
    final players = widget.gameModel.players;
    final positions = _calculatePlayerPositions(
      players.length,
      maxWidth,
      maxHeight,
    );

    return List.generate(players.length, (index) {
      final player = players[index];
      final position = positions[index];
      final isCurrentUser = player.userId == widget.currentUserId;
      final isCurrentPlayer =
          widget.gameModel.handInProgress &&
              index == widget.gameModel.currentPlayerIndex;
      final isDealerButton = index == widget.gameModel.dealerPosition;
      final isSmallBlind = index == widget.gameModel.smallBlindPosition;
      final isBigBlind = index == widget.gameModel.bigBlindPosition;

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
                      card: isCurrentUser || widget.gameModel.currentRound ==
                          BettingRound.showdown && !player.hasFolded
                          ? player.holeCards[0]
                          : null,
                      faceDown: !isCurrentUser &&
                          widget.gameModel.currentRound !=
                              BettingRound.showdown,
                      height: 70,
                      width: 50,
                    ),
                  // Second card
                  if (player.holeCards.length > 1)
                    PlayingCardWidget(
                      card: isCurrentUser || widget.gameModel.currentRound ==
                          BettingRound.showdown && !player.hasFolded
                          ? player.holeCards[1]
                          : null,
                      faceDown: !isCurrentUser &&
                          widget.gameModel.currentRound !=
                              BettingRound.showdown,
                      height: 70,
                      width: 50,
                    ),
                ],
              ),

              // Player's hand evaluation at showdown
              if (widget.gameModel.currentRound == BettingRound.showdown &&
                  !player.hasFolded &&
                  player.handEvaluation != null)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: widget.gameModel.winners.contains(player)
                        ? Colors.amber
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    player.handEvaluation!.displayName,
                    style: TextStyle(
                      color: widget.gameModel.winners.contains(player)
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
  List<Map<String, double>> _calculatePlayerPositions(int playerCount,
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
    final player = widget.gameModel.currentPlayer;
    final canCheck = widget.gameModel.canCheck();
    final callAmount = widget.gameModel.callAmount();
    final minRaise = widget.gameModel.minimumRaiseAmount();
    final bool canRaise = player.chipBalance >= minRaise;

    // Current big blind value for minimum bet
    final bigBlind = widget.gameModel.gameModel.bigBlind;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Minimum bet/raise info
          if (widget.gameModel.currentBet > 0)
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
                onPressed: () => widget.onAction('fold'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
                child: const Text('Fold'),
              ),

              const SizedBox(width: 8),

              // Check or Call button
              ElevatedButton(
                onPressed: canCheck
                    ? () => widget.onAction('check')
                    : callAmount > 0
                    ? () => widget.onAction('call')
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
                child: Text(widget.gameModel.currentBet > 0 ? 'Raise' : 'Bet'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Improved _showRaiseDialog method with better validation
  void _showRaiseDialog() {
    final TextEditingController raiseController = TextEditingController();
    final player = widget.gameModel.currentPlayer;

    // For a new bet, use the big blind as minimum
    final bigBlind = widget.gameModel.gameModel.bigBlind;
    final minAmount = widget.gameModel.currentBet > 0
        ? widget.gameModel.minimumRaiseAmount()
        : bigBlind;

    final maxRaise = player.chipBalance;

    // Set initial value to minimum amount
    raiseController.text = minAmount.toString();

    // Flag to track validation errors
    bool hasError = false;
    String errorMessage = '';

    // Make sure we have a valid context before showing dialog
    final BuildContext context = navigatorKey.currentContext ?? this.context;

    showDialog(
      context: context,
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
                  errorMessage = widget.gameModel.currentBet > 0
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
              title: Text(widget.gameModel.currentBet > 0
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
                    widget.gameModel.currentBet > 0
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
                      widget.onAction(
                        widget.gameModel.currentBet > 0 ? 'raise' : 'bet',
                        amount: amount,
                      );
                    } else {
                      // Validate one more time
                      validateAmount();
                    }
                  },
                  child: Text(
                      widget.gameModel.currentBet > 0 ? 'Raise' : 'Bet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Quick button to set specific amount with validation callback
  Widget _quickAmountButton(TextEditingController controller, int amount,
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

  // Improved game history dialog
  void _showHistoryDialog(BuildContext context) {
    // After the dialog is built, scroll to the end of the list
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToHistoryEnd();
    });

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
                  child: widget.gameModel.actionHistory.isEmpty
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
                    controller: _historyScrollController,
                    itemCount: widget.gameModel.actionHistory.length,
                    itemBuilder: (context, index) {
                      final action = widget.gameModel.actionHistory[index];
                      final username = action['player'] ?? 'Dealer';
                      final actionText = action['action'];
                      final amount = action['amount'];
                      final round = action['round'];
                      final isCurrentUser = username == widget.gameModel.players
                          .firstWhere(
                              (p) => p.userId == widget.currentUserId,
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
                            backgroundColor: _getActionColor(actionText),
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

  // Helper method to build round filter chips
  Widget _buildRoundFilterChip(String roundName) {
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
    } else if (action.contains('deal')) {
      return Colors.teal;
    } else {
      return Colors.grey;
    }
  }

  @override
  void dispose() {
    _historyScrollController.dispose();
    super.dispose();
  }
}