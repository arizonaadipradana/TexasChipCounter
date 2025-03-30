import 'dart:math' as Math;

import 'package:flutter/foundation.dart';
import 'player_model.dart';

enum GameStatus { pending, active, completed }

class GameModel {
  final String id;
  final String name;
  final String hostId;
  final List<Player> players;
  final int smallBlind;
  final int bigBlind;
  final DateTime createdAt;
  GameStatus status;
  int currentPlayerIndex;
  int? pot; // Add pot field
  int? currentBet; // Add currentBet field
  String? shortId; // Add shortId field

  GameModel({
    required this.id,
    required this.name,
    required this.hostId,
    required this.players,
    required this.smallBlind,
    required this.bigBlind,
    required this.createdAt,
    this.status = GameStatus.pending,
    this.currentPlayerIndex = 0,
    this.pot, // Default is null
    this.currentBet, // Default is null
    this.shortId, // Default is null
  });

  // Factory constructor to create a GameModel from JSON
  factory GameModel.fromJson(Map<String, dynamic> json) {
    // Handle different ID formats
    String id = json['_id'] ?? json['id'];
    if (id == null) {
      print('Warning: Game object missing ID field: $json');
      id = 'unknown';
    }

    try {
      // Extract shortId directly from the response if available
      String? shortId = json['shortId'];

      return GameModel(
        id: id,
        name: json['name'],
        hostId: json['hostId'],
        players: (json['players'] as List)
            .map((player) => Player.fromJson(player))
            .toList(),
        smallBlind: json['smallBlind'],
        bigBlind: json['bigBlind'],
        createdAt: DateTime.parse(json['createdAt']),
        status: GameStatus.values.byName(json['status']),
        currentPlayerIndex: json['currentPlayerIndex'] ?? 0,
        pot: json['pot'] != null ? int.tryParse(json['pot'].toString()) : null,
        currentBet: json['currentBet'] != null ? int.tryParse(json['currentBet'].toString()) : null,
        shortId: shortId, // Store the shortId if available
      );
    } catch (e) {
      print('Error parsing game JSON: $e');
      print('Problematic JSON: $json');
      rethrow;
    }
  }

  // Convert GameModel to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'hostId': hostId,
      'players': players.map((player) => player.toJson()).toList(),
      'smallBlind': smallBlind,
      'bigBlind': bigBlind,
      'createdAt': createdAt.toIso8601String(),
      'status': status.name,
      'currentPlayerIndex': currentPlayerIndex,
      'pot': pot,
      'currentBet': currentBet,
      'shortId': shortId, // Include shortId in JSON conversion
    };
  }

  // Get the game's short ID, or a fallback if not available
  String getShortId() {
    if (shortId != null && shortId!.isNotEmpty) {
      return shortId!;
    }
    // Fallback to first 6 chars of the full ID if no shortId is available
    // This is for backward compatibility
    return id.substring(0, Math.min(6, id.length)).toUpperCase();
  }

  // Add a player to the game
  void addPlayer(Player player) {
    if (!players.any((p) => p.userId == player.userId)) {
      players.add(player);
    }
  }

  // Remove a player from the game
  void removePlayer(String userId) {
    players.removeWhere((player) => player.userId == userId);
  }

  // Start the game
  void startGame() {
    status = GameStatus.active;
  }

  // End the game
  void endGame() {
    status = GameStatus.completed;
  }

  // Move to next player's turn
  void nextTurn() {
    currentPlayerIndex = (currentPlayerIndex + 1) % players.length;
  }

  // Get current player
  Player get currentPlayer => players[currentPlayerIndex];
}