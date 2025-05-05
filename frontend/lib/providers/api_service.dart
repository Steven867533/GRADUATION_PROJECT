import 'dart:convert';
import 'package:http/http.dart' as http;
import '../main.dart'; // For AppConfig

class ApiService {
  static const String baseUrl = AppConfig.baseUrl;
  static const String espUrl = AppConfig.espUrl;
  static final http.Client _client = http.Client();

  Future<Map<String, dynamic>> getUserProfile(String token) async {
    final url = '$baseUrl/users/me';
    print('Making GET request to $url with token: $token');
    final response = await _client.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );
    print('Response status: ${response.statusCode}, body: ${response.body}');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch user profile: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getCompanion(String token, String companionId) async {
    final url = '$baseUrl/users/$companionId';
    print('Making GET request to $url with token: $token');
    final response = await _client.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );
    print('Response status: ${response.statusCode}, body: ${response.body}');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch companion: ${response.body}');
    }
  }

  Future<List<dynamic>> getNearbyLocations(String token, double latitude, double longitude) async {
    final url = '$baseUrl/locations/nearby?latitude=$latitude&longitude=$longitude';
    print('Making GET request to $url with token: $token');
    final response = await _client.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );
    print('Response status: ${response.statusCode}, body: ${response.body}');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch nearby locations: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getBeatData() async {
    final url = '$espUrl/beat';
    final response = await _client.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch beat data');
    }
  }

  Future<Map<String, dynamic>> startReading(String token, double latitude, double longitude) async {
    final url = '$espUrl/readings';
    final response = await _client.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      // Save the reading to the backend
      final saveUrl = '$baseUrl/readings';
      final saveResponse = await _client.post(
        Uri.parse(saveUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'heartRate': data['heartRate'],
          'spo2': data['spo2'],
          'latitude': latitude,
          'longitude': longitude,
        }),
      );
      if (saveResponse.statusCode != 201) {
        throw Exception('Failed to save reading: ${saveResponse.body}');
      }
      return data;
    } else {
      throw Exception('Failed to start reading');
    }
  }

  Future<List<Map<String, dynamic>>> getReadings(String token, DateTime startDate, DateTime endDate, [String? patientId]) async {
    String url = '$baseUrl/readings?startDate=${startDate.toIso8601String()}&endDate=${endDate.toIso8601String()}';
    
    // If patientId is provided, add it to the query parameters
    if (patientId != null) {
      url += '&patientId=$patientId';
    }
    
    final response = await _client.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to fetch readings: ${response.body}');
    }
  }

  Future<List<String>> getReadingDates(String token) async {
    final url = '$baseUrl/readings/dates';
    final response = await _client.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return List<String>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to fetch reading dates: ${response.body}');
    }
  }

  Future<int> getUnseenMessageCount(String token) async {
    final url = '$baseUrl/messages/unseen-count';
    print('Making GET request to $url with token: $token');
    final response = await _client.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );
    print('Response status: ${response.statusCode}, body: ${response.body}');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['unseenCount'] ?? 0;
    } else {
      throw Exception('Failed to fetch unseen message count: ${response.body}');
    }
  }

  Future<bool> checkEspHealth() async {
    final url = '$espUrl/health';
    try {
      final response = await _client.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'UP';
      }
      return false;
    } catch (e) {
      print('Error checking ESP health: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> searchUsers(String token, String phoneNumber) async {
    final url = '$baseUrl/users/search?phoneNumber=$phoneNumber';
    final response = await _client.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to search users: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> updateUserProfile(String token, Map<String, dynamic> userData) async {
    final url = '$baseUrl/users/me';
    print('Making PUT request to $url with token: $token');
    final response = await _client.put(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(userData),
    );
    print('Response status: ${response.statusCode}, body: ${response.body}');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to update user profile: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getUserByPhone(String token, String phoneNumber) async {
    final url = '$baseUrl/users/by-phone?phoneNumber=$phoneNumber';
    print('Making GET request to $url with token: $token');
    final response = await _client.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );
    print('Response status: ${response.statusCode}, body: ${response.body}');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch user by phone: ${response.body}');
    }
  }
}