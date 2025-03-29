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
  final String? gameId;  // Mark explicitly as nullable

  Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.timestamp,
    required this.description,
    this.gameId,  // Nullable parameter
  });

  // Factory constructor to create a Transaction from JSON
  factory Transaction.fromJson(Map<String, dynamic> json) {
    // Get the ID field, handling different field names
    String transactionId = json['_id'] ?? json['id'] ?? '';

    // Get transaction type safely
    String typeStr = json['type'] ?? 'topUp';  // Default to topUp if missing
    TransactionType transactionType;
    try {
      transactionType = TransactionType.values.byName(typeStr);
    } catch (e) {
      // Default to topUp if the type string doesn't match any enum value
      transactionType = TransactionType.topUp;
    }

    // Handle timestamp safely
    DateTime timestampValue;
    try {
      timestampValue = json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now();
    } catch (e) {
      timestampValue = DateTime.now();
    }

    return Transaction(
      id: transactionId,
      type: transactionType,
      amount: json['amount'] ?? 0,  // Default to 0 if missing
      timestamp: timestampValue,
      description: json['description'] ?? 'Transaction',  // Default description if missing
      gameId: json['gameId'],  // This is already nullable, no need to use ?? here
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