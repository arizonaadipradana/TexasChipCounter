import 'card_model.dart';

// Represents the type of poker hand
enum HandRank {
  highCard,
  onePair,
  twoPair,
  threeOfAKind,
  straight,
  flush,
  fullHouse,
  fourOfAKind,
  straightFlush,
  royalFlush,
}

// Extension to get display name for hand rank
extension HandRankExtension on HandRank {
  String get displayName {
    switch (this) {
      case HandRank.highCard:
        return 'High Card';
      case HandRank.onePair:
        return 'One Pair';
      case HandRank.twoPair:
        return 'Two Pair';
      case HandRank.threeOfAKind:
        return 'Three of a Kind';
      case HandRank.straight:
        return 'Straight';
      case HandRank.flush:
        return 'Flush';
      case HandRank.fullHouse:
        return 'Full House';
      case HandRank.fourOfAKind:
        return 'Four of a Kind';
      case HandRank.straightFlush:
        return 'Straight Flush';
      case HandRank.royalFlush:
        return 'Royal Flush';
    }
  }
}

// Result of a hand evaluation, including the rank and the five cards that form the hand
class HandEvaluation {
  final HandRank rank;
  final List<Card> bestHand; // The 5 cards that form the best hand
  final List<Card> tiebreakers; // Cards in order of importance for breaking ties

  HandEvaluation({
    required this.rank,
    required this.bestHand,
    required this.tiebreakers,
  });

  // Compare two hands to determine which is better
  int compareTo(HandEvaluation other) {
    // First compare by hand rank
    final rankComparison = rank.index.compareTo(other.rank.index);
    if (rankComparison != 0) {
      return rankComparison;
    }

    // If ranks are the same, compare tiebreakers
    for (int i = 0; i < tiebreakers.length && i < other.tiebreakers.length; i++) {
      final cardComparison = tiebreakers[i].value.compareTo(other.tiebreakers[i].value);
      if (cardComparison != 0) {
        return cardComparison;
      }
    }

    // If all tiebreakers are the same, it's a tie
    return 0;
  }

  // Get a display name for the hand
  String get displayName => rank.displayName;

  // Convert to and from JSON
  Map<String, dynamic> toJson() {
    return {
      'rank': rank.index,
      'bestHand': bestHand.map((c) => c.toJson()).toList(),
      'tiebreakers': tiebreakers.map((c) => c.toJson()).toList(),
    };
  }

  factory HandEvaluation.fromJson(Map<String, dynamic> json) {
    return HandEvaluation(
      rank: HandRank.values[json['rank']],
      bestHand: (json['bestHand'] as List)
          .map((c) => Card.fromJson(c))
          .toList(),
      tiebreakers: (json['tiebreakers'] as List)
          .map((c) => Card.fromJson(c))
          .toList(),
    );
  }
}

// Class that evaluates poker hands
class HandEvaluator {
  // Evaluate the best 5-card hand from the given cards
  static HandEvaluation evaluate(List<Card> cards) {
    if (cards.length < 5) {
      throw ArgumentError('Need at least 5 cards to evaluate a poker hand');
    }

    // Get all possible 5-card combinations if more than 5 cards
    List<List<Card>> combinations = [];
    if (cards.length == 5) {
      combinations = [List.from(cards)];
    } else {
      combinations = _getCombinations(cards, 5);
    }

    // Evaluate each combination and find the best one
    HandEvaluation? bestHand;
    for (final combo in combinations) {
      final evaluation = _evaluateHand(combo);
      if (bestHand == null || evaluation.compareTo(bestHand) > 0) {
        bestHand = evaluation;
      }
    }

    return bestHand!;
  }

  // Generate all possible k-combinations from a list
  static List<List<Card>> _getCombinations(List<Card> cards, int k) {
    List<List<Card>> result = [];
    void backtrack(int start, List<Card> current) {
      if (current.length == k) {
        result.add(List.from(current));
        return;
      }
      for (int i = start; i < cards.length; i++) {
        current.add(cards[i]);
        backtrack(i + 1, current);
        current.removeLast();
      }
    }
    backtrack(0, []);
    return result;
  }

  // Evaluate a 5-card poker hand
  static HandEvaluation _evaluateHand(List<Card> hand) {
    // Check for each hand type from highest to lowest
    if (_isRoyalFlush(hand)) {
      final bestHand = _getStraightFlushCards(hand);
      return HandEvaluation(
        rank: HandRank.royalFlush,
        bestHand: bestHand,
        tiebreakers: bestHand, // Royal flush has no tiebreakers - all are equal
      );
    }

    if (_isStraightFlush(hand)) {
      final bestHand = _getStraightFlushCards(hand);
      return HandEvaluation(
        rank: HandRank.straightFlush,
        bestHand: bestHand,
        tiebreakers: [bestHand.first], // Highest card in straight flush
      );
    }

    if (_isFourOfAKind(hand)) {
      final result = _getFourOfAKindInfo(hand);
      return HandEvaluation(
        rank: HandRank.fourOfAKind,
        bestHand: hand, // All 5 cards
        tiebreakers: result['tiebreakers'] as List<Card>,
      );
    }

    if (_isFullHouse(hand)) {
      final result = _getFullHouseInfo(hand);
      return HandEvaluation(
        rank: HandRank.fullHouse,
        bestHand: hand, // All 5 cards
        tiebreakers: result['tiebreakers'] as List<Card>,
      );
    }

    if (_isFlush(hand)) {
      // For a flush, sort by rank (high to low) and use all cards as tiebreakers
      final sortedHand = List<Card>.from(hand)
        ..sort((a, b) => b.value.compareTo(a.value));
      return HandEvaluation(
        rank: HandRank.flush,
        bestHand: sortedHand,
        tiebreakers: sortedHand,
      );
    }

    if (_isStraight(hand)) {
      final bestHand = _getStraightCards(hand);
      return HandEvaluation(
        rank: HandRank.straight,
        bestHand: bestHand,
        tiebreakers: [bestHand.first], // Highest card in straight
      );
    }

    if (_isThreeOfAKind(hand)) {
      final result = _getThreeOfAKindInfo(hand);
      return HandEvaluation(
        rank: HandRank.threeOfAKind,
        bestHand: hand, // All 5 cards
        tiebreakers: result['tiebreakers'] as List<Card>,
      );
    }

    if (_isTwoPair(hand)) {
      final result = _getTwoPairInfo(hand);
      return HandEvaluation(
        rank: HandRank.twoPair,
        bestHand: hand, // All 5 cards
        tiebreakers: result['tiebreakers'] as List<Card>,
      );
    }

    if (_isOnePair(hand)) {
      final result = _getOnePairInfo(hand);
      return HandEvaluation(
        rank: HandRank.onePair,
        bestHand: hand, // All 5 cards
        tiebreakers: result['tiebreakers'] as List<Card>,
      );
    }

    // If no other hand, it's a high card
    final sortedHand = List<Card>.from(hand)
      ..sort((a, b) => b.value.compareTo(a.value));
    return HandEvaluation(
      rank: HandRank.highCard,
      bestHand: sortedHand,
      tiebreakers: sortedHand,
    );
  }

  // Check for royal flush (A, K, Q, J, 10 of the same suit)
  static bool _isRoyalFlush(List<Card> hand) {
    if (!_isStraightFlush(hand)) return false;

    // Sort by rank (high to low)
    final sortedHand = List<Card>.from(hand)
      ..sort((a, b) => b.value.compareTo(a.value));

    // Check if the highest card is an Ace
    return sortedHand.first.rank == CardRank.ace;
  }

  // Check for straight flush (5 consecutive cards of the same suit)
  static bool _isStraightFlush(List<Card> hand) {
    return _isFlush(hand) && _isStraight(hand);
  }

  // Get the straight flush cards in descending order
  static List<Card> _getStraightFlushCards(List<Card> hand) {
    // Sort by rank (high to low)
    final sortedHand = List<Card>.from(hand)
      ..sort((a, b) => b.value.compareTo(a.value));

    // Handle A-5-4-3-2 straight (Ace is low)
    if (_isLowStraight(hand)) {
      // Find the Ace
      final ace = sortedHand.firstWhere((c) => c.rank == CardRank.ace);
      // Remove the Ace from the beginning and put it at the end (as a low Ace)
      sortedHand.remove(ace);
      sortedHand.add(ace);
    }

    return sortedHand;
  }

  // Check for four of a kind (4 cards of the same rank)
  static bool _isFourOfAKind(List<Card> hand) {
    final rankCounts = _countRanks(hand);
    return rankCounts.values.any((count) => count == 4);
  }

  // Get information about a four of a kind hand
  static Map<String, dynamic> _getFourOfAKindInfo(List<Card> hand) {
    final rankCounts = _countRanks(hand);
    CardRank? fourOfAKindRank;

    for (final entry in rankCounts.entries) {
      if (entry.value == 4) {
        fourOfAKindRank = entry.key;
        break;
      }
    }

    // Cards from the four of a kind
    final fourCards = hand.where((c) => c.rank == fourOfAKindRank).toList();
    // The remaining card
    final kicker = hand.firstWhere((c) => c.rank != fourOfAKindRank);

    // Tiebreakers: four of a kind cards first, then kicker
    final tiebreakers = [...fourCards, kicker];

    return {
      'fourOfAKindRank': fourOfAKindRank,
      'tiebreakers': tiebreakers,
    };
  }

  // Check for full house (3 cards of one rank, 2 of another)
  static bool _isFullHouse(List<Card> hand) {
    final rankCounts = _countRanks(hand);
    return rankCounts.values.contains(3) && rankCounts.values.contains(2);
  }

  // Get information about a full house hand
  static Map<String, dynamic> _getFullHouseInfo(List<Card> hand) {
    final rankCounts = _countRanks(hand);
    CardRank? threeOfAKindRank;
    CardRank? pairRank;

    for (final entry in rankCounts.entries) {
      if (entry.value == 3) {
        threeOfAKindRank = entry.key;
      } else if (entry.value == 2) {
        pairRank = entry.key;
      }
    }

    // Cards from the three of a kind and pair
    final threeCards = hand.where((c) => c.rank == threeOfAKindRank).toList();
    final pairCards = hand.where((c) => c.rank == pairRank).toList();

    // Tiebreakers: three of a kind cards first, then pair cards
    final tiebreakers = [...threeCards, ...pairCards];

    return {
      'threeOfAKindRank': threeOfAKindRank,
      'pairRank': pairRank,
      'tiebreakers': tiebreakers,
    };
  }

  // Check for flush (5 cards of the same suit)
  static bool _isFlush(List<Card> hand) {
    final suits = hand.map((c) => c.suit).toSet();
    return suits.length == 1;
  }

  // Check for straight (5 consecutive cards)
  static bool _isStraight(List<Card> hand) {
    // Sort by rank (high to low)
    final sortedHand = List<Card>.from(hand)
      ..sort((a, b) => b.value.compareTo(a.value));

    // Check for A-5-4-3-2 straight (Ace is low)
    if (_isLowStraight(hand)) {
      return true;
    }

    // Check for consecutive cards
    for (int i = 0; i < sortedHand.length - 1; i++) {
      final diff = sortedHand[i].value - sortedHand[i + 1].value;
      if (diff != 1) {
        return false;
      }
    }

    return true;
  }

  // Check for A-5-4-3-2 straight (Ace is low)
  static bool _isLowStraight(List<Card> hand) {
    // Check for A, 5, 4, 3, 2
    final hasAce = hand.any((c) => c.rank == CardRank.ace);
    final has5 = hand.any((c) => c.rank == CardRank.five);
    final has4 = hand.any((c) => c.rank == CardRank.four);
    final has3 = hand.any((c) => c.rank == CardRank.three);
    final has2 = hand.any((c) => c.rank == CardRank.two);

    return hasAce && has5 && has4 && has3 && has2;
  }

  // Get the straight cards in descending order
  static List<Card> _getStraightCards(List<Card> hand) {
    // Sort by rank (high to low)
    final sortedHand = List<Card>.from(hand)
      ..sort((a, b) => b.value.compareTo(a.value));

    // Handle A-5-4-3-2 straight (Ace is low)
    if (_isLowStraight(hand)) {
      // Find the Ace
      final ace = sortedHand.firstWhere((c) => c.rank == CardRank.ace);
      // Find the other cards
      final five = sortedHand.firstWhere((c) => c.rank == CardRank.five);
      final four = sortedHand.firstWhere((c) => c.rank == CardRank.four);
      final three = sortedHand.firstWhere((c) => c.rank == CardRank.three);
      final two = sortedHand.firstWhere((c) => c.rank == CardRank.two);
      // Return in correct order (5 high, Ace low)
      return [five, four, three, two, ace];
    }

    return sortedHand;
  }

  // Check for three of a kind (3 cards of the same rank)
  static bool _isThreeOfAKind(List<Card> hand) {
    final rankCounts = _countRanks(hand);
    return rankCounts.values.contains(3) && !rankCounts.values.contains(2);
  }

  // Get information about a three of a kind hand
  static Map<String, dynamic> _getThreeOfAKindInfo(List<Card> hand) {
    final rankCounts = _countRanks(hand);
    CardRank? threeOfAKindRank;

    for (final entry in rankCounts.entries) {
      if (entry.value == 3) {
        threeOfAKindRank = entry.key;
        break;
      }
    }

    // Cards from the three of a kind
    final threeCards = hand.where((c) => c.rank == threeOfAKindRank).toList();
    // The remaining two cards (kickers)
    final kickers = hand.where((c) => c.rank != threeOfAKindRank).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Tiebreakers: three of a kind cards first, then kickers
    final tiebreakers = [...threeCards, ...kickers];

    return {
      'threeOfAKindRank': threeOfAKindRank,
      'tiebreakers': tiebreakers,
    };
  }

  // Check for two pair (2 cards of one rank, 2 of another)
  static bool _isTwoPair(List<Card> hand) {
    final rankCounts = _countRanks(hand);
    final pairs = rankCounts.values.where((count) => count == 2).length;
    return pairs == 2;
  }

  // Get information about a two pair hand
  static Map<String, dynamic> _getTwoPairInfo(List<Card> hand) {
    final rankCounts = _countRanks(hand);
    List<CardRank> pairRanks = [];

    for (final entry in rankCounts.entries) {
      if (entry.value == 2) {
        pairRanks.add(entry.key);
      }
    }

    // Sort pairs by rank (high to low)
    pairRanks.sort((a, b) => b.index.compareTo(a.index));

    // Cards from the high pair
    final highPairCards = hand.where((c) => c.rank == pairRanks[0]).toList();
    // Cards from the low pair
    final lowPairCards = hand.where((c) => c.rank == pairRanks[1]).toList();
    // The remaining card (kicker)
    final kicker = hand.firstWhere((c) => !pairRanks.contains(c.rank));

    // Tiebreakers: high pair cards first, then low pair cards, then kicker
    final tiebreakers = [...highPairCards, ...lowPairCards, kicker];

    return {
      'highPairRank': pairRanks[0],
      'lowPairRank': pairRanks[1],
      'tiebreakers': tiebreakers,
    };
  }

  // Check for one pair (2 cards of the same rank)
  static bool _isOnePair(List<Card> hand) {
    final rankCounts = _countRanks(hand);
    final pairs = rankCounts.values.where((count) => count == 2).length;
    return pairs == 1;
  }

  // Get information about a one pair hand
  static Map<String, dynamic> _getOnePairInfo(List<Card> hand) {
    final rankCounts = _countRanks(hand);
    CardRank? pairRank;

    for (final entry in rankCounts.entries) {
      if (entry.value == 2) {
        pairRank = entry.key;
        break;
      }
    }

    // Cards from the pair
    final pairCards = hand.where((c) => c.rank == pairRank).toList();
    // The remaining three cards (kickers)
    final kickers = hand.where((c) => c.rank != pairRank).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Tiebreakers: pair cards first, then kickers high to low
    final tiebreakers = [...pairCards, ...kickers];

    return {
      'pairRank': pairRank,
      'tiebreakers': tiebreakers,
    };
  }

  // Helper function to count occurrences of each rank
  static Map<CardRank, int> _countRanks(List<Card> hand) {
    Map<CardRank, int> counts = {};
    for (final card in hand) {
      counts[card.rank] = (counts[card.rank] ?? 0) + 1;
    }
    return counts;
  }
}