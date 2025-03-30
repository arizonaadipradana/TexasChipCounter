import 'dart:math' as Math;

import 'package:flutter/foundation.dart';

import 'card_model.dart';
import 'hand_evaluator.dart';
import 'player_model.dart';
import 'game_model.dart';

// Represents the current betting round in a poker game
enum BettingRound {
  preFlop,
  flop,
  turn,
  river,
  showdown,
}

// Extension to get display name for the betting round
extension BettingRoundExtension on BettingRound {
  String get displayName {
    switch (this) {
      case BettingRound.preFlop:
        return 'Pre-Flop';
      case BettingRound.flop:
        return 'Flop';
      case BettingRound.turn:
        return 'Turn';
      case BettingRound.river:
        return 'River';
      case BettingRound.showdown:
        return 'Showdown';
    }
  }
}

// Represents a player in the poker game with additional poker-specific properties
class PokerPlayer extends Player {
  List<Card> holeCards = []; // Private cards for the player
  HandEvaluation? handEvaluation; // Evaluation of the player's best hand
  bool hasFolded = false; // Whether the player has folded
  int currentBet = 0; // How much the player has bet in the current round
  int totalBet = 0; // Total amount bet in the current hand
  bool hasActed = false; // Whether the player has acted in the current round
  bool isAllIn = false; // Whether the player is all-in

  PokerPlayer({
    required String userId,
    required String username,
    required int chipBalance,
    bool isActive = true,
  }) : super(
    userId: userId,
    username: username,
    chipBalance: chipBalance,
    isActive: isActive,
  );

  // Create a PokerPlayer from a regular Player
  factory PokerPlayer.fromPlayer(Player player) {
    return PokerPlayer(
      userId: player.userId,
      username: player.username,
      chipBalance: player.chipBalance,
      isActive: player.isActive,
    );
  }

  // Reset player state for a new hand
  void resetForNewHand() {
    holeCards = [];
    handEvaluation = null;
    hasFolded = false;
    currentBet = 0;
    totalBet = 0;
    hasActed = false;
    isAllIn = false;
  }

  // Place a bet (returns true if successful, false if not enough chips)
  bool placeBet(int amount) {
    if (amount > chipBalance) {
      return false;
    }

    currentBet += amount;
    totalBet += amount;
    chipBalance -= amount;
    hasActed = true;

    // Check if player is now all-in
    if (chipBalance == 0) {
      isAllIn = true;
    }

    return true;
  }

  // Check (pass on betting)
  void check() {
    hasActed = true;
  }

  // Fold (give up on the hand)
  void fold() {
    hasFolded = true;
    hasActed = true;
  }

  // Convert to and from JSON
  @override
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = super.toJson();
    json.addAll({
      'holeCards': holeCards.map((c) => c.toJson()).toList(),
      'handEvaluation': handEvaluation?.toJson(),
      'hasFolded': hasFolded,
      'currentBet': currentBet,
      'totalBet': totalBet,
      'hasActed': hasActed,
      'isAllIn': isAllIn,
    });
    return json;
  }

  factory PokerPlayer.fromJson(Map<String, dynamic> json) {
    final player = PokerPlayer(
      userId: json['userId'],
      username: json['username'],
      chipBalance: json['chipBalance'],
      isActive: json['isActive'] ?? true,
    );

    // Add poker-specific properties if available
    if (json.containsKey('holeCards')) {
      player.holeCards = (json['holeCards'] as List)
          .map((c) => Card.fromJson(c))
          .toList();
    }

    if (json.containsKey('handEvaluation') && json['handEvaluation'] != null) {
      player.handEvaluation = HandEvaluation.fromJson(json['handEvaluation']);
    }

    player.hasFolded = json['hasFolded'] ?? false;
    player.currentBet = json['currentBet'] ?? 0;
    player.totalBet = json['totalBet'] ?? 0;
    player.hasActed = json['hasActed'] ?? false;
    player.isAllIn = json['isAllIn'] ?? false;

    return player;
  }

  // Create a copy with the same properties
  PokerPlayer copy() {
    final player = PokerPlayer(
      userId: userId,
      username: username,
      chipBalance: chipBalance,
      isActive: isActive,
    );

    player.holeCards = List.from(holeCards);
    player.handEvaluation = handEvaluation;
    player.hasFolded = hasFolded;
    player.currentBet = currentBet;
    player.totalBet = totalBet;
    player.hasActed = hasActed;
    player.isAllIn = isAllIn;

    return player;
  }
}

// Represents a poker game with Texas Hold'em rules
class PokerGameModel extends ChangeNotifier {
  final GameModel gameModel; // Base game model
  late List<PokerPlayer> players; // List of poker players

  // Poker-specific properties
  Deck deck = Deck(); // Deck of cards
  List<Card> communityCards = []; // Shared cards on the table
  BettingRound currentRound = BettingRound.preFlop; // Current betting round
  int pot = 0; // Total pot size
  List<int> sidePots = []; // Side pots for all-in situations
  List<PokerPlayer> winners = []; // Winners of the current hand
  int dealerPosition = 0; // Position of the dealer button
  int smallBlindPosition = 1; // Position of the small blind
  int bigBlindPosition = 2; // Position of the big blind
  int currentPlayerIndex = 0; // Index of the current player to act
  int currentBet = 0; // Current bet amount that players need to match
  int minRaise = 0; // Minimum raise amount
  bool handInProgress = false; // Whether a hand is currently in progress

  // Game history
  List<Map<String, dynamic>> actionHistory = []; // History of player actions

  PokerGameModel({required this.gameModel}) {
    // Convert regular players to poker players
    players = gameModel.players
        .map((p) => PokerPlayer.fromPlayer(p))
        .toList();

    // Initialize positions
    if (players.length >= 3) {
      dealerPosition = 0;
      smallBlindPosition = 1;
      bigBlindPosition = 2;
      currentPlayerIndex = (bigBlindPosition + 1) % players.length;
    } else if (players.length == 2) {
      // Heads-up (2 players)
      dealerPosition = 0;
      smallBlindPosition = 0; // Dealer posts small blind
      bigBlindPosition = 1;
      currentPlayerIndex = 0; // Dealer acts first pre-flop
    }
  }

  // Get the current betting round name
  String get currentRoundName => currentRound.displayName;

  // Get the player who's currently acting
  PokerPlayer get currentPlayer => players[currentPlayerIndex];

  // Get the player who's the dealer
  PokerPlayer get dealer => players[dealerPosition];

  // Get the player who's the small blind
  PokerPlayer get smallBlind => players[smallBlindPosition];

  // Get the player who's the big blind
  PokerPlayer get bigBlind => players[bigBlindPosition];

  // Get active players (not folded and still have chips or are all-in)
  List<PokerPlayer> get activePlayers {
    return players.where((p) =>
    p.isActive && !p.hasFolded
    ).toList();
  }

  // Get players who haven't folded (for showdown)
  List<PokerPlayer> get playersInHand {
    return players.where((p) => !p.hasFolded).toList();
  }

  // Start a new hand
  void startNewHand() {
    // Reset player states
    for (final player in players) {
      player.resetForNewHand();
    }

    // Reset game state
    deck = Deck();
    deck.shuffle();
    communityCards = [];
    currentRound = BettingRound.preFlop;
    pot = 0;
    sidePots = [];
    winners = [];
    currentBet = 0;
    minRaise = gameModel.bigBlind;
    actionHistory = [];

    // Move positions for the next hand
    _movePositions();

    // Deal hole cards to each player
    for (final player in players) {
      if (player.isActive && player.chipBalance > 0) {
        player.holeCards = deck.dealMultiple(2);
      }
    }

    // Post blinds
    _postBlinds();

    // Set the first player to act (after big blind)
    currentPlayerIndex = (bigBlindPosition + 1) % players.length;
    _skipInactivePlayers();

    handInProgress = true;
    notifyListeners();
  }

  // Post the blinds to start the hand
  void _postBlinds() {
    // Small blind
    final sbPlayer = players[smallBlindPosition];
    if (sbPlayer.isActive && sbPlayer.chipBalance > 0) {
      final sbAmount = Math.min(gameModel.smallBlind, sbPlayer.chipBalance);
      sbPlayer.placeBet(sbAmount);
      pot += sbAmount;
      _addToHistory(sbPlayer, 'posts small blind', sbAmount);
    }

    // Big blind
    final bbPlayer = players[bigBlindPosition];
    if (bbPlayer.isActive && bbPlayer.chipBalance > 0) {
      final bbAmount = Math.min(gameModel.bigBlind, bbPlayer.chipBalance);
      bbPlayer.placeBet(bbAmount);
      pot += bbAmount;
      currentBet = bbAmount;
      _addToHistory(bbPlayer, 'posts big blind', bbAmount);
    }
  }

  // Move the dealer and blind positions for the next hand
  void _movePositions() {
    // Find the next active player for the dealer position
    int nextDealer = (dealerPosition + 1) % players.length;
    while (!players[nextDealer].isActive || players[nextDealer].chipBalance <= 0) {
      nextDealer = (nextDealer + 1) % players.length;
      if (nextDealer == dealerPosition) break; // Safety check
    }
    dealerPosition = nextDealer;

    // Set small blind and big blind positions
    if (players.length >= 3) {
      // Normal game
      smallBlindPosition = _findNextActivePosition(dealerPosition);
      bigBlindPosition = _findNextActivePosition(smallBlindPosition);
    } else if (players.length == 2) {
      // Heads-up (2 players)
      smallBlindPosition = dealerPosition; // Dealer is small blind
      bigBlindPosition = _findNextActivePosition(dealerPosition); // Other player is big blind
    }
  }

  // Find the next active player position
  int _findNextActivePosition(int currentPosition) {
    int nextPosition = (currentPosition + 1) % players.length;
    while (!players[nextPosition].isActive || players[nextPosition].chipBalance <= 0) {
      nextPosition = (nextPosition + 1) % players.length;
      if (nextPosition == currentPosition) break; // Safety check
    }
    return nextPosition;
  }

  // Skip inactive or folded players
  void _skipInactivePlayers() {
    int count = 0;
    while (count < players.length) {
      final player = players[currentPlayerIndex];
      if (player.isActive && !player.hasFolded && player.chipBalance > 0 && !player.isAllIn) {
        break;
      }
      currentPlayerIndex = (currentPlayerIndex + 1) % players.length;
      count++;
    }
  }

  // Check if this player can check (no current bet to call)
  bool canCheck() {
    return currentPlayer.currentBet == currentBet;
  }

  // Calculate the amount needed to call
  int callAmount() {
    return Math.min(currentBet - currentPlayer.currentBet, currentPlayer.chipBalance);
  }

  // Calculate the minimum raise amount
  int minimumRaiseAmount() {
    final toCall = callAmount();
    return toCall + minRaise;
  }

  // Handle a player's action
  void performAction(String action, {int? amount}) {
    final player = currentPlayer;

    switch (action) {
      case 'fold':
        player.fold();
        _addToHistory(player, 'folds');
        break;

      case 'check':
        if (!canCheck()) {
          throw ArgumentError('Cannot check when there is a bet to call');
        }
        player.check();
        _addToHistory(player, 'checks');
        break;

      case 'call':
        final callAmt = callAmount();
        if (callAmt > 0) {
          player.placeBet(callAmt);
          pot += callAmt;
          _addToHistory(player, 'calls', callAmt);
        } else {
          player.check();
          _addToHistory(player, 'checks');
        }
        break;

      case 'raise':
        if (amount == null || amount < minimumRaiseAmount()) {
          throw ArgumentError('Raise amount must be at least the minimum raise');
        }

        final raiseAmt = Math.min(amount, player.chipBalance);
        player.placeBet(raiseAmt);
        pot += raiseAmt;
        currentBet = player.currentBet;
        minRaise = player.currentBet - currentBet;
        _addToHistory(player, 'raises to', player.currentBet);

        // Reset hasActed for all players except all-ins and folds
        for (final p in players) {
          if (!p.hasFolded && !p.isAllIn && p.userId != player.userId) {
            p.hasActed = false;
          }
        }
        break;

      case 'bet':
        if (currentBet > 0) {
          throw ArgumentError('Cannot bet when there is already a bet. Use raise instead.');
        }

        if (amount == null || amount < gameModel.bigBlind) {
          throw ArgumentError('Bet amount must be at least the big blind');
        }

        final betAmt = Math.min(amount, player.chipBalance);
        player.placeBet(betAmt);
        pot += betAmt;
        currentBet = betAmt;
        minRaise = gameModel.bigBlind;
        _addToHistory(player, 'bets', betAmt);

        // Reset hasActed for all players except all-ins and folds
        for (final p in players) {
          if (!p.hasFolded && !p.isAllIn && p.userId != player.userId) {
            p.hasActed = false;
          }
        }
        break;
    }

    // Move to the next player
    _moveToNextPlayer();

    // Check if the betting round is complete
    if (_isBettingRoundComplete()) {
      _advanceToNextRound();
    }

    notifyListeners();
  }

  // Move to the next player who can act
  void _moveToNextPlayer() {
    currentPlayerIndex = (currentPlayerIndex + 1) % players.length;
    _skipInactivePlayers();
  }

  // Check if all players have acted or folded
  bool _isBettingRoundComplete() {
    // Count how many players are still in the hand, not all-in, and have not acted
    int playersToAct = 0;

    for (final player in players) {
      if (player.isActive && !player.hasFolded && !player.isAllIn) {
        if (!player.hasActed) {
          playersToAct++;
        } else if (player.currentBet != currentBet) {
          // Player has acted but hasn't matched the current bet
          playersToAct++;
        }
      }
    }

    return playersToAct == 0;
  }

  // Advance to the next betting round
  void _advanceToNextRound() {
    // Reset player bets for the new round
    for (final player in players) {
      player.currentBet = 0;
      player.hasActed = false;
    }

    currentBet = 0;

    switch (currentRound) {
      case BettingRound.preFlop:
        currentRound = BettingRound.flop;
        // Deal the flop (3 community cards)
        communityCards.addAll(deck.dealMultiple(3));
        _addToHistory(null, 'deals the flop', null);
        break;

      case BettingRound.flop:
        currentRound = BettingRound.turn;
        // Deal the turn (1 community card)
        communityCards.add(deck.deal()!);
        _addToHistory(null, 'deals the turn', null);
        break;

      case BettingRound.turn:
        currentRound = BettingRound.river;
        // Deal the river (1 community card)
        communityCards.add(deck.deal()!);
        _addToHistory(null, 'deals the river', null);
        break;

      case BettingRound.river:
        currentRound = BettingRound.showdown;
        // Showdown
        _evaluateHands();
        _determineWinners();
        _distributePot();

        // Hand is complete
        handInProgress = false;
        break;

      case BettingRound.showdown:
      // Hand is already complete
        break;
    }

    // Set the first player to act in the new round
    if (currentRound != BettingRound.showdown) {
      // After the flop, action starts with the small blind or the next active player
      if (players.length >= 3) {
        currentPlayerIndex = smallBlindPosition;
      } else {
        // In heads-up, action starts with the dealer/small blind
        currentPlayerIndex = dealerPosition;
      }
      _skipInactivePlayers();
    }
  }

  // Evaluate each player's hand
  void _evaluateHands() {
    for (final player in playersInHand) {
      // Combine hole cards and community cards
      final allCards = [...player.holeCards, ...communityCards];

      // Evaluate the best 5-card hand
      player.handEvaluation = HandEvaluator.evaluate(allCards);

      _addToHistory(player, 'shows ${player.handEvaluation!.displayName}', null);
    }
  }

  // Determine the winner(s) of the hand
  void _determineWinners() {
    if (playersInHand.length == 1) {
      // Only one player left, they win by default
      winners = [playersInHand[0]];
      _addToHistory(winners[0], 'wins the pot', pot);
      return;
    }

    // Compare hand evaluations to find the winner(s)
    HandEvaluation? bestHand;

    for (final player in playersInHand) {
      if (player.handEvaluation == null) continue;

      if (bestHand == null ||
          player.handEvaluation!.compareTo(bestHand) > 0) {
        bestHand = player.handEvaluation;
        winners = [player];
      } else if (player.handEvaluation!.compareTo(bestHand) == 0) {
        // Tie, add this player as a co-winner
        winners.add(player);
      }
    }

    // Log the winners
    if (winners.length == 1) {
      _addToHistory(winners[0], 'wins the pot with ${winners[0].handEvaluation!.displayName}', pot);
    } else if (winners.length > 1) {
      final winnerNames = winners.map((p) => p.username).join(', ');
      _addToHistory(null, '$winnerNames tie and split the pot', pot);
    }
  }

  // Distribute the pot to the winner(s)
  void _distributePot() {
    if (winners.isEmpty) return;

    if (winners.length == 1) {
      // Single winner gets the whole pot
      winners[0].chipBalance += pot;
    } else {
      // Multiple winners split the pot as evenly as possible
      final splitAmount = pot ~/ winners.length;
      int remainder = pot % winners.length;

      for (final winner in winners) {
        winner.chipBalance += splitAmount;

        // Distribute remainder one chip at a time
        if (remainder > 0) {
          winner.chipBalance += 1;
          remainder--;
        }
      }
    }

    pot = 0;
  }

  // Check if the hand is over early (everyone folded except one player)
  bool checkForEarlyWin() {
    final activePlayers = players.where((p) => !p.hasFolded).toList();

    if (activePlayers.length == 1) {
      // Only one player left, they win by default
      winners = [activePlayers[0]];
      winners[0].chipBalance += pot;
      _addToHistory(winners[0], 'wins the pot (all others folded)', pot);
      pot = 0;
      handInProgress = false;
      notifyListeners();
      return true;
    }

    return false;
  }

  // Add an action to the history
  void _addToHistory(PokerPlayer? player, String action, [int? amount]) {
    actionHistory.add({
      'player': player?.username,
      'action': action,
      'amount': amount,
      'round': currentRoundName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // Convert to and from JSON
  Map<String, dynamic> toJson() {
    return {
      'gameModel': gameModel.toJson(),
      'players': players.map((p) => p.toJson()).toList(),
      'communityCards': communityCards.map((c) => c.toJson()).toList(),
      'currentRound': currentRound.index,
      'pot': pot,
      'sidePots': sidePots,
      'winners': winners.map((p) => p.userId).toList(),
      'dealerPosition': dealerPosition,
      'smallBlindPosition': smallBlindPosition,
      'bigBlindPosition': bigBlindPosition,
      'currentPlayerIndex': currentPlayerIndex,
      'currentBet': currentBet,
      'minRaise': minRaise,
      'handInProgress': handInProgress,
      'actionHistory': actionHistory,
    };
  }

  factory PokerGameModel.fromJson(Map<String, dynamic> json) {
    final gameModel = GameModel.fromJson(json['gameModel']);
    final pokerGame = PokerGameModel(gameModel: gameModel);

    pokerGame.players = (json['players'] as List)
        .map((p) => PokerPlayer.fromJson(p))
        .toList();

    pokerGame.communityCards = (json['communityCards'] as List)
        .map((c) => Card.fromJson(c))
        .toList();

    pokerGame.currentRound = BettingRound.values[json['currentRound']];
    pokerGame.pot = json['pot'];
    pokerGame.sidePots = List<int>.from(json['sidePots']);

    // Convert winner IDs back to player references
    final winnerIds = List<String>.from(json['winners']);
    pokerGame.winners = pokerGame.players
        .where((p) => winnerIds.contains(p.userId))
        .toList();

    pokerGame.dealerPosition = json['dealerPosition'];
    pokerGame.smallBlindPosition = json['smallBlindPosition'];
    pokerGame.bigBlindPosition = json['bigBlindPosition'];
    pokerGame.currentPlayerIndex = json['currentPlayerIndex'];
    pokerGame.currentBet = json['currentBet'];
    pokerGame.minRaise = json['minRaise'];
    pokerGame.handInProgress = json['handInProgress'];
    pokerGame.actionHistory = List<Map<String, dynamic>>.from(json['actionHistory']);

    return pokerGame;
  }
}