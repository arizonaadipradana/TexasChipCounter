import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/game_service_core.dart';
import '../services/transaction_service.dart';
import 'create_game_screen.dart';
import 'join_game_screen.dart';
import 'profile_screen.dart';
import 'transaction_history_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Clear any cached game IDs when returning to home screen
    GameService.clearGameIdCache();
  }

  void _logout(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final userModel = Provider.of<UserModel>(context, listen: false);

    await authService.logout();
    userModel.logout();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  void _showTopUpDialog(BuildContext context) {
    final TextEditingController amountController = TextEditingController();
    final userModel = Provider.of<UserModel>(context, listen: false);
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
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
                enabled: !isLoading,
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
              onPressed: isLoading ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () async {
                final rupiahAmount = int.tryParse(amountController.text) ?? 0;
                if (rupiahAmount > 0) {
                  setState(() {
                    isLoading = true;
                  });

                  final chipAmount = (rupiahAmount / 500).floor();

                  // Create transaction service instance
                  final transactionService = TransactionService();

                  // Call the server API for top-up
                  final result = await transactionService.topUp(
                      chipAmount,
                      userModel.authToken!
                  );

                  // Pop the dialog whether successful or not
                  Navigator.of(ctx).pop();

                  if (result['success']) {
                    // Update chip balance in user model only after confirmed by server
                    userModel.updateChipBalance(result['chipBalance']);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Added $chipAmount chips successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(result['message']),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid amount'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: isLoading
                  ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white
                  )
              )
                  : const Text('Top Up'),
            ),
          ],
        ),
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

  @override
  Widget build(BuildContext context) {
    final userModel = Provider.of<UserModel>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nyanguni Kancane'),
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
                    'Buat Lobby LG',
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
                    'Join Lobby',
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
                    'Riwayat Transaksi',
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
                    'Profil',
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
}