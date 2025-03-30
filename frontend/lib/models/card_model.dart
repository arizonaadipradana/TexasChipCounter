// Represents card suits in a standard deck
enum CardSuit {
  hearts,
  diamonds,
  clubs,
  spades,
}

// Represents card ranks in a standard deck
enum CardRank {
  two,
  three,
  four,
  five,
  six,
  seven,
  eight,
  nine,
  ten,
  jack,
  queen,
  king,
  ace,
}

// A playing card with a suit and rank
class Card {
  final CardSuit suit;
  final CardRank rank;

  Card({required this.suit, required this.rank});

  // Create a card from a string representation (e.g., "AS" for Ace of Spades)
  factory Card.fromString(String cardStr) {
    if (cardStr.length != 2) {
      throw ArgumentError('Invalid card string: $cardStr');
    }

    final rankChar = cardStr[0].toUpperCase();
    final suitChar = cardStr[1].toLowerCase();

    CardRank rank;
    switch (rankChar) {
      case '2':
        rank = CardRank.two;
        break;
      case '3':
        rank = CardRank.three;
        break;
      case '4':
        rank = CardRank.four;
        break;
      case '5':
        rank = CardRank.five;
        break;
      case '6':
        rank = CardRank.six;
        break;
      case '7':
        rank = CardRank.seven;
        break;
      case '8':
        rank = CardRank.eight;
        break;
      case '9':
        rank = CardRank.nine;
        break;
      case 'T':
        rank = CardRank.ten;
        break;
      case 'J':
        rank = CardRank.jack;
        break;
      case 'Q':
        rank = CardRank.queen;
        break;
      case 'K':
        rank = CardRank.king;
        break;
      case 'A':
        rank = CardRank.ace;
        break;
      default:
        throw ArgumentError('Invalid rank: $rankChar');
    }

    CardSuit suit;
    switch (suitChar) {
      case 'h':
        suit = CardSuit.hearts;
        break;
      case 'd':
        suit = CardSuit.diamonds;
        break;
      case 'c':
        suit = CardSuit.clubs;
        break;
      case 's':
        suit = CardSuit.spades;
        break;
      default:
        throw ArgumentError('Invalid suit: $suitChar');
    }

    return Card(suit: suit, rank: rank);
  }

  // Convert to string representation
  String toString() {
    String rankStr;
    switch (rank) {
      case CardRank.two:
        rankStr = '2';
        break;
      case CardRank.three:
        rankStr = '3';
        break;
      case CardRank.four:
        rankStr = '4';
        break;
      case CardRank.five:
        rankStr = '5';
        break;
      case CardRank.six:
        rankStr = '6';
        break;
      case CardRank.seven:
        rankStr = '7';
        break;
      case CardRank.eight:
        rankStr = '8';
        break;
      case CardRank.nine:
        rankStr = '9';
        break;
      case CardRank.ten:
        rankStr = 'T';
        break;
      case CardRank.jack:
        rankStr = 'J';
        break;
      case CardRank.queen:
        rankStr = 'Q';
        break;
      case CardRank.king:
        rankStr = 'K';
        break;
      case CardRank.ace:
        rankStr = 'A';
        break;
    }

    String suitStr;
    switch (suit) {
      case CardSuit.hearts:
        suitStr = 'h';
        break;
      case CardSuit.diamonds:
        suitStr = 'd';
        break;
      case CardSuit.clubs:
        suitStr = 'c';
        break;
      case CardSuit.spades:
        suitStr = 's';
        break;
    }

    return '$rankStr$suitStr';
  }

  // Get a nice display name for the card
  String get displayName {
    String rankStr;
    switch (rank) {
      case CardRank.two:
        rankStr = '2';
        break;
      case CardRank.three:
        rankStr = '3';
        break;
      case CardRank.four:
        rankStr = '4';
        break;
      case CardRank.five:
        rankStr = '5';
        break;
      case CardRank.six:
        rankStr = '6';
        break;
      case CardRank.seven:
        rankStr = '7';
        break;
      case CardRank.eight:
        rankStr = '8';
        break;
      case CardRank.nine:
        rankStr = '9';
        break;
      case CardRank.ten:
        rankStr = '10';
        break;
      case CardRank.jack:
        rankStr = 'J';
        break;
      case CardRank.queen:
        rankStr = 'Q';
        break;
      case CardRank.king:
        rankStr = 'K';
        break;
      case CardRank.ace:
        rankStr = 'A';
        break;
    }

    String suitStr;
    switch (suit) {
      case CardSuit.hearts:
        suitStr = '♥';
        break;
      case CardSuit.diamonds:
        suitStr = '♦';
        break;
      case CardSuit.clubs:
        suitStr = '♣';
        break;
      case CardSuit.spades:
        suitStr = '♠';
        break;
    }

    return '$rankStr$suitStr';
  }

  // Get the color of the card (red for hearts/diamonds, black for clubs/spades)
  bool get isRed => suit == CardSuit.hearts || suit == CardSuit.diamonds;

  // Convert to and from JSON
  Map<String, dynamic> toJson() {
    return {
      'suit': suit.index,
      'rank': rank.index,
    };
  }

  factory Card.fromJson(Map<String, dynamic> json) {
    return Card(
      suit: CardSuit.values[json['suit']],
      rank: CardRank.values[json['rank']],
    );
  }

  // Equality operator
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Card) return false;
    return suit == other.suit && rank == other.rank;
  }

  @override
  int get hashCode => suit.hashCode ^ rank.hashCode;

  // Numerical value for comparing cards, with Ace high
  int get value => rank.index;
}

// A deck of cards that can be shuffled and dealt
class Deck {
  List<Card> cards = [];

  // Create a new deck with all 52 cards
  Deck() {
    reset();
  }

  // Reset the deck to a full, unshuffled state
  void reset() {
    cards.clear();
    for (var suit in CardSuit.values) {
      for (var rank in CardRank.values) {
        cards.add(Card(suit: suit, rank: rank));
      }
    }
  }

  // Shuffle the deck
  void shuffle() {
    cards.shuffle();
  }

  // Deal a single card from the deck
  Card? deal() {
    if (cards.isEmpty) {
      return null;
    }
    return cards.removeLast();
  }

  // Deal multiple cards at once
  List<Card> dealMultiple(int count) {
    final result = <Card>[];
    for (int i = 0; i < count; i++) {
      final card = deal();
      if (card != null) {
        result.add(card);
      } else {
        break;
      }
    }
    return result;
  }

  // Return the number of cards left in the deck
  int get remainingCards => cards.length;

  // Create from JSON
  factory Deck.fromJson(Map<String, dynamic> json) {
    final deck = Deck();
    deck.cards = (json['cards'] as List)
        .map((cardJson) => Card.fromJson(cardJson))
        .toList();
    return deck;
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'cards': cards.map((card) => card.toJson()).toList(),
    };
  }
}