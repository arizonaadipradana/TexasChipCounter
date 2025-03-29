import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/transaction_model.dart';

class TransactionService {
  // Get user's transaction history
  Future<Map<String, dynamic>> getUserTransactions(
      String userId,
      String authToken, {
        int limit = 10,
        int page = 1,
      }) async {
    try {
      final response = await http.get(
        Uri.parse(
            '${ApiConfig.baseUrl}${ApiConfig.transactionsEndpoint}/user/$userId?limit=$limit&page=$page'
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        List<Transaction> transactions = (responseData['transactions'] as List)
            .map((transaction) => Transaction.fromJson(transaction))
            .toList();

        return {
          'success': true,
          'transactions': transactions,
          'pagination': responseData['pagination'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to get transaction history',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Get transaction details
  Future<Map<String, dynamic>> getTransaction(
      String transactionId,
      String authToken,
      ) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.transactionsEndpoint}/$transactionId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'transaction': Transaction.fromJson(responseData['transaction']),
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to get transaction details',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Get game transactions
  Future<Map<String, dynamic>> getGameTransactions(
      String gameId,
      String authToken,
      ) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.transactionsEndpoint}/game/$gameId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        List<Transaction> transactions = (responseData['transactions'] as List)
            .map((transaction) => Transaction.fromJson(transaction))
            .toList();

        return {
          'success': true,
          'transactions': transactions,
          'gameSummary': responseData['gameSummary'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to get game transactions',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Top up user's chip balance
  Future<Map<String, dynamic>> topUp(
      int chipAmount,
      String authToken,
      ) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.topUpEndpoint}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'amount': chipAmount,
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': responseData['message'],
          'chipBalance': responseData['chipBalance'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to top up',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }
}