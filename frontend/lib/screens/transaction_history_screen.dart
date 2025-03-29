import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/transaction_model.dart';
import '../models/user_model.dart';
import '../services/transaction_service.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({Key? key}) : super(key: key);

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  bool _isLoading = true;
  List<Transaction> _transactions = [];
  String _errorMessage = '';
  int _page = 1;
  int _limit = 10;
  bool _hasMoreTransactions = true;

  @override
  void initState() {
    super.initState();
    _fetchTransactionHistory();
  }

  Future<void> _fetchTransactionHistory({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _page = 1;
        _hasMoreTransactions = true;
      });
    }

    if (!_hasMoreTransactions && !refresh) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    // Get user model and auth token
    final userModel = Provider.of<UserModel>(context, listen: false);

    if (userModel.authToken == null || userModel.id == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'You need to be logged in to view transaction history';
      });
      return;
    }

    // Create transaction service
    final transactionService = TransactionService();

    try {
      // Get real transactions from the server API
      final result = await transactionService.getUserTransactions(
        userModel.id!,
        userModel.authToken!,
        limit: _limit,
        page: _page,
      );

      setState(() {
        _isLoading = false;

        if (result['success']) {
          final newTransactions = result['transactions'] as List<Transaction>;

          if (refresh) {
            _transactions = newTransactions;
          } else {
            _transactions = [..._transactions, ...newTransactions];
          }

          // Check if there are more transactions to load
          final pagination = result['pagination'];
          if (pagination != null) {
            _hasMoreTransactions = _page < (pagination['totalPages'] ?? 1);
          } else {
            _hasMoreTransactions = newTransactions.length >= _limit;
          }

          // Increment page for next load
          _page++;
        } else {
          _errorMessage = result['message'] ?? 'Unknown error occurred';
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: ${e.toString()}';
      });
      print('Error in transaction history: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _fetchTransactionHistory(refresh: true),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading && _transactions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty && _transactions.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _fetchTransactionHistory(refresh: true),
              child: const Text('Try Again'),
            ),
          ],
        ),
      )
          : _transactions.isEmpty
          ? const Center(
        child: Text(
          'No transactions found',
          style: TextStyle(fontSize: 16),
        ),
      )
          : RefreshIndicator(
        onRefresh: () => _fetchTransactionHistory(refresh: true),
        child: ListView.builder(
          itemCount: _transactions.length + (_isLoading || _hasMoreTransactions ? 1 : 0),
          itemBuilder: (context, index) {
            // Show loading indicator at the bottom while loading more
            if (index == _transactions.length) {
              if (_isLoading) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              } else if (_hasMoreTransactions) {
                // Load more when reaching the end
                _fetchTransactionHistory();
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              return const SizedBox.shrink();
            }

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
      ),
    );
  }
}