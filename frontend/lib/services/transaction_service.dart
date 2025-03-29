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

      // Print the API response for debugging
      print('Transaction history API response: ${response.body}');

      try {
        final responseData = jsonDecode(response.body);

        if (response.statusCode == 200 && responseData['success'] == true) {
          // Safe parsing of transactions with error handling
          List<Transaction> transactions = [];

          if (responseData['transactions'] != null && responseData['transactions'] is List) {
            for (var transactionJson in responseData['transactions']) {
              try {
                transactions.add(Transaction.fromJson(transactionJson));
              } catch (e) {
                print('Error parsing individual transaction: $e');
                print('Problematic transaction JSON: $transactionJson');
                // Continue parsing other transactions
              }
            }
          }

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
        print('Error parsing JSON response: $e');
        return {
          'success': false,
          'message': 'Error parsing server response: ${e.toString()}',
        };
      }
    } catch (e) {
      print('Network or other error in getUserTransactions: $e');
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

      if (response.statusCode == 200 && responseData['success'] == true) {
        try {
          return {
            'success': true,
            'transaction': Transaction.fromJson(responseData['transaction']),
          };
        } catch (e) {
          print('Error parsing transaction: $e');
          return {
            'success': false,
            'message': 'Error parsing transaction data: ${e.toString()}',
          };
        }
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

      if (response.statusCode == 200 && responseData['success'] == true) {
        List<Transaction> transactions = [];

        // Safely parse transactions
        if (responseData['transactions'] != null && responseData['transactions'] is List) {
          for (var transactionJson in responseData['transactions']) {
            try {
              transactions.add(Transaction.fromJson(transactionJson));
            } catch (e) {
              print('Error parsing individual game transaction: $e');
              // Continue parsing other transactions
            }
          }
        }

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

      print('Top-up API response: ${response.body}');

      try {
        final responseData = jsonDecode(response.body);

        if (response.statusCode == 200 && responseData['success'] == true) {
          return {
            'success': true,
            'message': responseData['message'] ?? 'Top-up successful',
            'chipBalance': responseData['chipBalance'] ?? 0,
          };
        } else {
          return {
            'success': false,
            'message': responseData['message'] ?? 'Failed to top up',
          };
        }
      } catch (e) {
        print('Error parsing top-up response: $e');
        return {
          'success': false,
          'message': 'Error processing server response: ${e.toString()}',
        };
      }
    } catch (e) {
      print('Network error in topUp: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }
}