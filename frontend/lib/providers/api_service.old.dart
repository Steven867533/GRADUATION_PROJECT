import 'dart:convert';
import 'package:HCE/main.dart';
import 'package:http/http.dart' as http;

class ApiService {
  // static const String baseUrl = 'http://10.0.2.2:5000';
  // static const String espUrl = 'http://10.0.2.2:5001';
  static const String baseUrl = AppConfig.baseUrl;
  static const String espUrl = AppConfig.espUrl;
  
  // Singleton HTTP client
  static final http.Client _client = http.Client();

  // Helper method to make authenticated GET requests
  Future<Map<String, dynamic>> _authenticatedGet(
      String endpoint, String token) async {
    final url = Uri.parse('$baseUrl$endpoint');
    print('Making GET request to $url with token: $token');
    final response = await _client.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    print('Response status: ${response.statusCode}, body: ${response.body}');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 401) {
      throw Exception('Unauthorized: ${response.body}');
    }
    throw Exception('Failed to load data from $endpoint: ${response.body}');
  }

  Future<Map<String, dynamic>> getUserProfile(String token) async {
    if (token.isEmpty) {
      throw Exception('Token is empty');
    }
    return _authenticatedGet('/users/me', token);
  }

  Future<Map<String, dynamic>> getCompanion(
      String token, String companionId) async {
    if (token.isEmpty) {
      throw Exception('Token is empty');
    }
    return _authenticatedGet('/users/$companionId', token);
  }

  Future<List<dynamic>> getNearbyLocations(
      String token, double latitude, double longitude) async {
    if (token.isEmpty) {
      throw Exception('Token is empty');
    }
    final endpoint =
        '/locations/nearby?latitude=$latitude&longitude=$longitude';
    final url = Uri.parse('$baseUrl$endpoint');
    print('Making GET request to $url with token: $token');
    final response = await _client.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    print('Response status: ${response.statusCode}, body: ${response.body}');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 401) {
      throw Exception('Unauthorized: ${response.body}');
    }
    throw Exception('Failed to load nearby locations: ${response.body}');
  }

  Future<Map<String, dynamic>> getBeatData() async {
    final url = Uri.parse('$espUrl/beat');
    print('Making GET request to $url (no token required)');
    final response = await _client.get(url);
    print('Response status: ${response.statusCode}, body: ${response.body}');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to fetch beat data: ${response.body}');
  }

  Future<Map<String, dynamic>> startReading() async {
    final url = Uri.parse('$espUrl/readings');
    print('Making GET request to $url (no token required)');
    final response = await _client.get(url);
    print('Response status: ${response.statusCode}, body: ${response.body}');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to start reading: ${response.body}');
  }

  Future<int> getUnseenMessageCount(String token) async {
    if (token.isEmpty) {
      throw Exception('Token is empty');
    }
    final url = Uri.parse('$baseUrl/messages/unseen-count');
    print('Making GET request to $url with token: $token');
    final response = await _client.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    print('Response status: ${response.statusCode}, body: ${response.body}');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['unseenCount'] ?? 0;
    } else if (response.statusCode == 401) {
      throw Exception('Unauthorized: ${response.body}');
    }
    throw Exception('Failed to fetch unseen message count: ${response.body}');
  }
}
