import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../config/api_config.dart';

class AuthService {
  // Keys for storing auth tokens and expiration
  static const String _authTokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _tokenExpiryKey = 'token_expiry';

  // Function to check if token is expired or about to expire (within 5 minutes)
  Future<bool> isTokenExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final expiryString = prefs.getString(_tokenExpiryKey);

    if (expiryString == null) {
      return true; // No expiry time, consider it expired
    }

    try {
      final expiryTime = DateTime.parse(expiryString);
      final now = DateTime.now();

      // Consider token expired if it expires within the next 5 minutes
      return now.isAfter(expiryTime.subtract(Duration(minutes: 5)));
    } catch (e) {
      print('Error parsing token expiry: $e');
      return true; // Error parsing, consider it expired
    }
  }

  // Extract expiry time from JWT token
  DateTime? _getTokenExpiry(String token) {
    try {
      // JWT tokens consist of three parts separated by dots
      final parts = token.split('.');
      if (parts.length != 3) {
        return null;
      }

      // Decode the payload (middle part)
      String normalizedPayload = base64Url.normalize(parts[1]);
      final payloadJson = utf8.decode(base64Url.decode(normalizedPayload));
      final payload = jsonDecode(payloadJson);

      // Extract expiration timestamp (exp claim)
      if (payload['exp'] != null) {
        // exp is in seconds since epoch, convert to milliseconds
        return DateTime.fromMillisecondsSinceEpoch(payload['exp'] * 1000);
      }

      return null;
    } catch (e) {
      print('Error extracting token expiry: $e');
      return null;
    }
  }

  // Refresh token function
  Future<Map<String, dynamic>> refreshToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString(_refreshTokenKey);

      if (refreshToken == null) {
        return {
          'success': false,
          'message': 'No refresh token available',
        };
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/users/refresh-token'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'refreshToken': refreshToken,
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final newToken = responseData['token'];

        // Extract and save the expiry time
        final expiryTime = _getTokenExpiry(newToken);
        if (expiryTime != null) {
          await prefs.setString(_tokenExpiryKey, expiryTime.toIso8601String());
          print('Token expiry set to: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(expiryTime)}');
        }

        // Save the new token
        await prefs.setString(_authTokenKey, newToken);

        return {
          'success': true,
          'token': newToken,
        };
      } else {
        // Clear tokens on refresh failure
        await prefs.remove(_authTokenKey);
        await prefs.remove(_refreshTokenKey);
        await prefs.remove(_tokenExpiryKey);

        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to refresh token',
        };
      }
    } catch (e) {
      print('Error refreshing token: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Register a new user with refresh token handling
  Future<Map<String, dynamic>> register(
      String username, String email, String password) async {
    try {
      print("Register request initiated: $email");
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/users/register'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password,
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 201) {
        // Extract token expiry time
        final expiryTime = _getTokenExpiry(responseData['token']);

        // Save the auth token, refresh token, and expiry
        await _saveAuthToken(responseData['token']);
        if (responseData['refreshToken'] != null) {
          await _saveRefreshToken(responseData['refreshToken']);
        }

        if (expiryTime != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_tokenExpiryKey, expiryTime.toIso8601String());
          print('Token expiry set to: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(expiryTime)}');
        }

        return {
          'success': true,
          'user': responseData['user'],
          'token': responseData['token'],
          'refreshToken': responseData['refreshToken'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Registration failed',
        };
      }
    } catch (e) {
      print('Registration error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Login user with refresh token handling
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      print("Login request initiated: $email");
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/users/login'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Extract token expiry time
        final expiryTime = _getTokenExpiry(responseData['token']);

        // Save the auth token and refresh token
        await _saveAuthToken(responseData['token']);
        if (responseData['refreshToken'] != null) {
          await _saveRefreshToken(responseData['refreshToken']);
        }

        if (expiryTime != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_tokenExpiryKey, expiryTime.toIso8601String());
          print('Token expiry set to: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(expiryTime)}');
        }

        return {
          'success': true,
          'user': responseData['user'],
          'token': responseData['token'],
          'refreshToken': responseData['refreshToken'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Login failed',
        };
      }
    } catch (e) {
      print('Login error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Save auth token to SharedPreferences
  Future<void> _saveAuthToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authTokenKey, token);
  }

  // Save refresh token to SharedPreferences
  Future<void> _saveRefreshToken(String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_refreshTokenKey, refreshToken);
  }

  // Logout - remove all tokens
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_tokenExpiryKey);
  }

  // Check if user is logged in with valid token
  Future<bool> isLoggedIn() async {
    final token = await getAuthToken();
    if (token == null) return false;

    // Check if token is expired
    if (await isTokenExpired()) {
      // Try to refresh the token
      final refreshResult = await refreshToken();
      return refreshResult['success'] == true;
    }

    return true;
  }

  // Get stored auth token
  Future<String?> getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_authTokenKey);
  }

  // Get stored refresh token
  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  // Get current user data with token refresh handling
  Future<Map<String, dynamic>> getUserData() async {
    try {
      // Check if token is expired and refresh if needed
      if (await isTokenExpired()) {
        final refreshResult = await refreshToken();
        if (!refreshResult['success']) {
          return {
            'success': false,
            'message': 'Session expired. Please log in again.',
          };
        }
      }

      final token = await getAuthToken();
      if (token == null) {
        return {
          'success': false,
          'message': 'No authentication token found',
        };
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/users/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'user': responseData['user'],
        };
      } else if (response.statusCode == 401) {
        // Try one more token refresh on 401
        final refreshResult = await refreshToken();
        if (refreshResult['success']) {
          // Retry with new token
          return getUserData();
        } else {
          return {
            'success': false,
            'message': 'Session expired. Please log in again.',
          };
        }
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to fetch user data',
        };
      }
    } catch (e) {
      print('Error getting user data: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Check and refresh token if needed before API calls
  Future<String?> getValidAuthToken() async {
    // Check if token is expired
    if (await isTokenExpired()) {
      // Try to refresh token
      final refreshResult = await refreshToken();
      if (refreshResult['success']) {
        return refreshResult['token'];
      } else {
        return null; // Token refresh failed
      }
    }

    // Token is still valid
    return getAuthToken();
  }
}