import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import '../config/api_config.dart';

// API Client with automatic token refresh
class ApiClient {
  final AuthService _authService = AuthService();

  // GET request with token refresh
  Future<http.Response> get(String endpoint, {Map<String, String>? headers}) async {
    // Get valid token (refreshes if needed)
    final token = await _authService.getValidAuthToken();

    if (token == null) {
      // Token refresh failed, throw unauthorized exception
      throw UnauthorizedException('Session expired. Please login again.');
    }

    // Prepare headers with authentication
    final Map<String, String> requestHeaders = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      ...?headers,
    };

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}$endpoint'),
        headers: requestHeaders,
      );

      // Handle 401 Unauthorized
      if (response.statusCode == 401) {
        // Try to refresh token one more time
        final refreshed = await _authService.refreshToken();
        if (refreshed['success']) {
          // Retry with new token
          return get(endpoint, headers: headers);
        } else {
          throw UnauthorizedException('Session expired. Please login again.');
        }
      }

      return response;
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // POST request with token refresh
  Future<http.Response> post(
      String endpoint,
      dynamic body,
      {Map<String, String>? headers}
      ) async {
    // Get valid token (refreshes if needed)
    final token = await _authService.getValidAuthToken();

    if (token == null) {
      // Token refresh failed, throw unauthorized exception
      throw UnauthorizedException('Session expired. Please login again.');
    }

    // Prepare headers with authentication
    final Map<String, String> requestHeaders = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      ...?headers,
    };

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}$endpoint'),
        headers: requestHeaders,
        body: jsonEncode(body),
      );

      // Handle 401 Unauthorized
      if (response.statusCode == 401) {
        // Try to refresh token one more time
        final refreshed = await _authService.refreshToken();
        if (refreshed['success']) {
          // Retry with new token
          return post(endpoint, body, headers: headers);
        } else {
          throw UnauthorizedException('Session expired. Please login again.');
        }
      }

      return response;
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // PUT request with token refresh
  Future<http.Response> put(
      String endpoint,
      dynamic body,
      {Map<String, String>? headers}
      ) async {
    // Get valid token (refreshes if needed)
    final token = await _authService.getValidAuthToken();

    if (token == null) {
      // Token refresh failed, throw unauthorized exception
      throw UnauthorizedException('Session expired. Please login again.');
    }

    // Prepare headers with authentication
    final Map<String, String> requestHeaders = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      ...?headers,
    };

    try {
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}$endpoint'),
        headers: requestHeaders,
        body: jsonEncode(body),
      );

      // Handle 401 Unauthorized
      if (response.statusCode == 401) {
        // Try to refresh token one more time
        final refreshed = await _authService.refreshToken();
        if (refreshed['success']) {
          // Retry with new token
          return put(endpoint, body, headers: headers);
        } else {
          throw UnauthorizedException('Session expired. Please login again.');
        }
      }

      return response;
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // DELETE request with token refresh
  Future<http.Response> delete(
      String endpoint,
      {Map<String, String>? headers}
      ) async {
    // Get valid token (refreshes if needed)
    final token = await _authService.getValidAuthToken();

    if (token == null) {
      // Token refresh failed, throw unauthorized exception
      throw UnauthorizedException('Session expired. Please login again.');
    }

    // Prepare headers with authentication
    final Map<String, String> requestHeaders = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      ...?headers,
    };

    try {
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}$endpoint'),
        headers: requestHeaders,
      );

      // Handle 401 Unauthorized
      if (response.statusCode == 401) {
        // Try to refresh token one more time
        final refreshed = await _authService.refreshToken();
        if (refreshed['success']) {
          // Retry with new token
          return delete(endpoint, headers: headers);
        } else {
          throw UnauthorizedException('Session expired. Please login again.');
        }
      }

      return response;
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      throw Exception('Network error: ${e.toString()}');
    }
  }
}

// Custom exception for authentication errors
class UnauthorizedException implements Exception {
  final String message;

  UnauthorizedException(this.message);

  @override
  String toString() => message;
}