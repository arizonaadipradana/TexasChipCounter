enum TransactionType {
  topUp,
  gameTransaction,
}

class Transaction {
  final String id;
  final TransactionType type;
  final int amount;
  final DateTime timestamp;
  final String description;
  final String? gameId;

  Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.timestamp,
    required this.description,
    this.gameId,
  });

  // Factory constructor to create a Transaction from JSON
  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'],
      type: TransactionType.values.byName(json['type']),
      amount: json['amount'],
      timestamp: DateTime.parse(json['timestamp']),
      description: json['description'],
      gameId: json['gameId'],
    );
  }

  // Convert Transaction to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'amount': amount,
      'timestamp': timestamp.toIso8601String(),
      'description': description,
      'gameId': gameId,
    };
  }
}