import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import 'create_game_screen.dart';
import 'join_game_screen.dart';
import 'profile_screen.dart';
import 'transaction_history_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  void _logout(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final userModel = Provider.of<UserModel>(context, listen: false);

    await authService.logout();
    userModel.logout();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userModel = Provider.of<UserModel>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Poker Chip Counter'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Hello, ${userModel.username ?? "Player"}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${userModel.chipBalance} chips',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _buildMenuCard(
                    context,
                    'Create Game',
                    Icons.add_circle,
                    Colors.green,
                        () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const CreateGameScreen(),
                        ),
                      );
                    },
                  ),
                  _buildMenuCard(
                    context,
                    'Join Game',
                    Icons.group_add,
                    Colors.blue,
                        () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const JoinGameScreen(),
                        ),
                      );
                    },
                  ),
                  _buildMenuCard(
                    context,
                    'Top Up Chips',
                    Icons.attach_money,
                    Colors.amber,
                        () {
                      _showTopUpDialog(context);
                    },
                  ),
                  _buildMenuCard(
                    context,
                    'Transaction History',
                    Icons.history,
                    Colors.purple,
                        () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const TransactionHistoryScreen(),
                        ),
                      );
                    },
                  ),
                  _buildMenuCard(
                    context,
                    'Profile',
                    Icons.person,
                    Colors.teal,
                        () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const ProfileScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard(
      BuildContext context,
      String title,
      IconData icon,
      Color color,
      VoidCallback onTap,
      ) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 48,
              color: color,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showTopUpDialog(BuildContext context) {
    final TextEditingController amountController = TextEditingController();
    final userModel = Provider.of<UserModel>(context, listen: false);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Top Up Chips'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter amount to top up (in rupiah):'),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                prefixText: 'Rp ',
                hintText: '50000',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Note: 1 chip = 500 rupiah',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final rupiahAmount = int.tryParse(amountController.text) ?? 0;
              if (rupiahAmount > 0) {
                final chipAmount = (rupiahAmount / 500).floor();
                userModel.addChips(chipAmount);
                Navigator.of(ctx).pop();

                // Here you would typically call an API to update the server
                // For now, we're just updating the local state
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Added $chipAmount chips successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid amount'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Top Up'),
          ),
        ],
      ),
    );
  }
}