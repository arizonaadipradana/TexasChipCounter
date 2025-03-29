class Player {
  final String userId;
  final String username;
  int chipBalance;
  bool isActive;

  Player({
    required this.userId,
    required this.username,
    required this.chipBalance,
    this.isActive = true,
  });

  // Factory constructor to create a Player from JSON
  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      userId: json['userId'],
      username: json['username'],
      chipBalance: json['chipBalance'],
      isActive: json['isActive'] ?? true,
    );
  }

  // Convert Player to JSON
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'chipBalance': chipBalance,
      'isActive': isActive,
    };
  }

  // Add chips to player's balance
  void addChips(int amount) {
    chipBalance += amount;
  }

  // Remove chips from player's balance
  bool removeChips(int amount) {
    if (chipBalance >= amount) {
      chipBalance -= amount;
      return true;
    }
    return false; // Not enough chips
  }

  // Set player as inactive
  void setInactive() {
    isActive = false;
  }

  // Set player as active
  void setActive() {
    isActive = true;
  }
}