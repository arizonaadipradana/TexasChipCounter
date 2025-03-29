import 'package:flutter/foundation.dart';

class UserModel extends ChangeNotifier {
  String? _id;
  String? _username;
  String? _email;
  int _chipBalance = 0;
  bool _isAuthenticated = false;
  String? _authToken;

  // Getters
  String? get id => _id;
  String? get username => _username;
  String? get email => _email;
  int get chipBalance => _chipBalance;
  bool get isAuthenticated => _isAuthenticated;
  String? get authToken => _authToken;

  // Set user data after login or registration
  void setUser({
    required String id,
    required String username,
    required String email,
    required int chipBalance,
    required String authToken,
  }) {
    _id = id;
    _username = username;
    _email = email;
    _chipBalance = chipBalance;
    _authToken = authToken;
    _isAuthenticated = true;
    notifyListeners();
  }

  // Update chip balance
  void updateChipBalance(int newBalance) {
    _chipBalance = newBalance;
    notifyListeners();
  }

  // Add chips (top-up)
  void addChips(int amount) {
    _chipBalance += amount;
    notifyListeners();
  }

  // Subtract chips (game transactions)
  bool subtractChips(int amount) {
    if (_chipBalance >= amount) {
      _chipBalance -= amount;
      notifyListeners();
      return true;
    }
    return false; // Not enough chips
  }

  // Logout
  void logout() {
    _id = null;
    _username = null;
    _email = null;
    _chipBalance = 0;
    _authToken = null;
    _isAuthenticated = false;
    notifyListeners();
  }
}