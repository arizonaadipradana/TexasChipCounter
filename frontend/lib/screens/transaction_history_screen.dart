import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/transaction_model.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({Key? key}) : super(key: key);

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  bool _isLoading = true;
  List<Transaction> _transactions = [];

  @override
  void initState() {
    super.initState();
    _fetchTransactionHistory();
  }

  Future<void> _fetchTransactionHistory() async {
    // In a real app, you would fetch transaction data from an API
    // For now, we'll simulate a delay and use mock data
    await Future.delayed(const Duration(seconds: 1));

    setState(() {
      _transactions = [
        Transaction(
          id: '1',
          type: TransactionType.topUp,
          amount: 100,
          timestamp: DateTime.now().subtract(const Duration(days: 1)),
          description: 'Top-up',
          gameId: null,
        ),
        Transaction(
          id: '2',
          type: TransactionType.gameTransaction,
          amount: -20,
          timestamp: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
          description: 'Game: Poker Night',
          gameId: 'game123',
        ),
        Transaction(
          id: '3',
          type: TransactionType.topUp,
          amount: 50,
          timestamp: DateTime.now().subtract(const Duration(days: 3)),
          description: 'Top-up',
          gameId: null,
        ),
        Transaction(
          id: '4',
          type: TransactionType.gameTransaction,
          amount: 35,
          timestamp: DateTime.now().subtract(const Duration(days: 3, hours: 1)),
          description: 'Game: Weekend Game',
          gameId: 'game456',
        ),
      ];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _transactions.isEmpty
          ? const Center(
        child: Text(
          'No transactions found',
          style: TextStyle(fontSize: 16),
        ),
      )
          : ListView.builder(
        itemCount: _transactions.length,
        itemBuilder: (context, index) {
          final transaction = _transactions[index];
          final isPositive = transaction.amount > 0;

          return Card(
            margin: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isPositive ? Colors.green : Colors.red,
                child: Icon(
                  isPositive ? Icons.add : Icons.remove,
                  color: Colors.white,
                ),
              ),
              title: Text(transaction.description),
              subtitle: Text(
                DateFormat('MMM dd, yyyy - HH:mm').format(transaction.timestamp),
              ),
              trailing: Text(
                '${isPositive ? '+' : ''}${transaction.amount} chips',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isPositive ? Colors.green : Colors.red,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}