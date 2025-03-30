import 'package:flutter/material.dart';

// Import with a prefix to avoid naming conflicts
import '../models/card_model.dart' as poker;

class PlayingCardWidget extends StatelessWidget {
  final poker.Card? card;
  final bool faceDown;
  final double height;
  final double width;
  final bool showShadow;
  final VoidCallback? onTap;

  const PlayingCardWidget({
    Key? key,
    this.card,
    this.faceDown = false,
    this.height = 80,
    this.width = 60,
    this.showShadow = true,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        width: width,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: faceDown ? Colors.blue.shade800 : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Colors.black,
            width: 1,
          ),
          boxShadow: showShadow
              ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(2, 2),
            ),
          ]
              : null,
        ),
        child: faceDown || card == null
            ? _buildCardBack()
            : _buildCardFace(card!),
      ),
    );
  }

  // Build the back of the card
  Widget _buildCardBack() {
    return Center(
      child: Icon(
        Icons.all_inclusive,
        color: Colors.white.withOpacity(0.8),
        size: width * 0.5,
      ),
    );
  }

  // Build the face of the card
  Widget _buildCardFace(poker.Card card) {
    final Color cardColor = card.isRed ? Colors.red : Colors.black;

    // Get suit symbol
    String suitSymbol;
    switch (card.suit) {
      case poker.CardSuit.hearts:
        suitSymbol = '♥';
        break;
      case poker.CardSuit.diamonds:
        suitSymbol = '♦';
        break;
      case poker.CardSuit.clubs:
        suitSymbol = '♣';
        break;
      case poker.CardSuit.spades:
        suitSymbol = '♠';
        break;
      default:
        suitSymbol = '?'; // Default value to avoid null error
        break;
    }

    // Get rank symbol
    String rankSymbol;
    switch (card.rank) {
      case poker.CardRank.ace:
        rankSymbol = 'A';
        break;
      case poker.CardRank.king:
        rankSymbol = 'K';
        break;
      case poker.CardRank.queen:
        rankSymbol = 'Q';
        break;
      case poker.CardRank.jack:
        rankSymbol = 'J';
        break;
      case poker.CardRank.ten:
        rankSymbol = '10';
        break;
      default:
      // For number cards, convert the enum index + 2 to get the value
        rankSymbol = (card.rank.index + 2).toString();
    }

    return Stack(
      children: [
        // Top left corner
        Positioned(
          top: 2,
          left: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                rankSymbol,
                style: TextStyle(
                  color: cardColor,
                  fontSize: width * 0.25,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                suitSymbol,
                style: TextStyle(
                  color: cardColor,
                  fontSize: width * 0.25,
                  height: 0.8,
                ),
              ),
            ],
          ),
        ),

        // Center suit
        Center(
          child: Text(
            suitSymbol,
            style: TextStyle(
              color: cardColor,
              fontSize: width * 0.5,
            ),
          ),
        ),

        // Bottom right corner (upside down)
        Positioned(
          bottom: 2,
          right: 4,
          child: Transform.rotate(
            angle: 3.14159, // 180 degrees in radians
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  rankSymbol,
                  style: TextStyle(
                    color: cardColor,
                    fontSize: width * 0.25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  suitSymbol,
                  style: TextStyle(
                    color: cardColor,
                    fontSize: width * 0.25,
                    height: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}