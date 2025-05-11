import 'dart:convert';
import 'package:http/http.dart' as http;
import '../main.dart'; // For AppConfig

class ApiService {
  static const String baseUrl = AppConfig.baseUrl;
  static final http.Client _client = http.Client();

  // Get the current ESP URL
  Future<String> getEspUrl() async {
    return await AppConfig.getEspUrl();
  }

  Future<Map<String, dynamic>> getUserProfile(String token) async {
    final url = '$baseUrl/users/me';
    print('Making GET request to $url with token: $token');

    try {
      final response = await _client.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      print('Response status: ${response.statusCode}, body: ${response.body}');
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch user profile: ${response.body}');
      }
    } catch (e) {
      print('Error fetching user profile: $e');
      throw Exception('Connection error: $e');
    }
  }

  Future<Map<String, dynamic>> getCompanion(
      String token, String companionId) async {
    final url = '$baseUrl/users/$companionId';
    print('Making GET request to $url with token: $token');

    try {
      final response = await _client.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10)); // Add timeout

      print('Response status: ${response.statusCode}, body: ${response.body}');
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch companion: ${response.body}');
      }
    } catch (e) {
      print('Error fetching companion: $e');
      // Return empty data instead of throwing exception to prevent UI crashes
      return {
        'name': 'Unavailable',
        'phoneNumber': 'Connection Error',
        '_id': companionId
      };
    }
  }

  Future<List<dynamic>> getNearbyLocations(
      String token, double latitude, double longitude) async {
    final url =
        '$baseUrl/locations/nearby?latitude=$latitude&longitude=$longitude';
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
    final espUrl = await getEspUrl();
    final url = '$espUrl/beat';
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 3)); // Shorter timeout for beat data
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch beat data');
      }
    } catch (e) {
      print('Error fetching beat data: $e');
      throw Exception('Connection error: $e');
    }
  }

  Future<Map<String, dynamic>> startReading(
      String token, double latitude, double longitude) async {
    final espUrl = await getEspUrl();
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

  Future<List<Map<String, dynamic>>> getReadings(
      String token, DateTime startDate, DateTime endDate,
      [String? patientId]) async {
    String url =
        '$baseUrl/readings?startDate=${startDate.toIso8601String()}&endDate=${endDate.toIso8601String()}';

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

  Future<List<String>> getReadingDates(String token,
      [String? patientId]) async {
    String url = '$baseUrl/readings/dates';

    // If patientId is provided, add it to the query parameters
    if (patientId != null) {
      url += '?patientId=$patientId';
    }

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
    final espUrl = await getEspUrl();
    final url = '$espUrl/health';
    try {
      final response = await _client.get(Uri.parse(url)).timeout(
          const Duration(seconds: 5)); // Shorter timeout for health check
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

  Future<List<Map<String, dynamic>>> searchUsers(
      String token, String phoneNumber) async {
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

  Future<Map<String, dynamic>> updateUserProfile(
      String token, Map<String, dynamic> userData) async {
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

  Future<Map<String, dynamic>> getUserByPhone(
      String token, String phoneNumber) async {
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

  // New method to get WebSocket URL from the ESP URL
  Future<String> getWebSocketUrl() async {
    final espUrl = await getEspUrl();
    final wsPort = await AppConfig.getWsPort();

    // Convert HTTP URL to WebSocket URL
    try {
      final uri = Uri.parse(espUrl);
      // Use the host part with the WebSocket port
      return 'ws://${uri.host}:$wsPort';
    } catch (e) {
      print('Error parsing ESP URL: $e');
      // Fallback: replace http:// with ws:// and use default port 81
      String wsUrl = espUrl.replaceFirst('http://', 'ws://');
      if (!wsUrl.contains(':81')) {
        // Replace the port if it exists, otherwise add it
        if (wsUrl.contains(':')) {
          wsUrl = wsUrl.replaceFirst(RegExp(r':\d+'), ':$wsPort');
        } else {
          wsUrl = '$wsUrl:$wsPort';
        }
      }
      return wsUrl;
    }
  }

  // New method to start a non-blocking reading using the updated sensor API
  Future<Map<String, dynamic>> startNonBlockingReading() async {
    final espUrl = await getEspUrl();
    final url = '$espUrl/readings';
    final response = await _client.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to start reading: ${response.body}');
    }
  }

  // New method to get the results of a completed reading
  Future<Map<String, dynamic>> getReadingResults() async {
    final espUrl = await getEspUrl();
    final url = '$espUrl/results';
    final response = await _client.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get reading results: ${response.body}');
    }
  }

  // New method to clear measurement results after they've been read
  Future<void> clearReadingResults() async {
    final espUrl = await getEspUrl();
    final url = '$espUrl/clear_results';
    try {
      final response =
          await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        print('Measurement results cleared successfully');
      } else {
        print('Failed to clear results: ${response.statusCode}');
      }
    } catch (e) {
      print('Error clearing measurement results: $e');
    }
  }

  // Get users who have sent unseen messages
  Future<List<Map<String, dynamic>>> getUnseenMessageSenders(
      String token) async {
    final url = '$baseUrl/messages/unseen-persons';
    print('Making GET request to $url with token: $token');

    try {
      final response = await _client.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10)); // Add a timeout

      print('Response status: ${response.statusCode}, body: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        print('Decoded ${data.length} unseen message senders successfully');

        if (data.isEmpty) {
          print(
              'Warning: No unseen message senders were returned from the API');
        }

        return List<Map<String, dynamic>>.from(data);
      } else {
        print(
            'Error fetching unseen message senders: HTTP ${response.statusCode}');
        throw Exception(
            'Failed to fetch unseen message senders: ${response.body}');
      }
    } catch (e) {
      print('Exception fetching unseen message senders: $e');
      // Return empty list instead of throwing to prevent UI crashes
      return [];
    }
  }

  // Mark all messages from a sender as seen
  Future<void> markAllMessagesAsSeen(String token, String senderId) async {
    final url = '$baseUrl/messages/mark-all-seen/$senderId';
    print('Making PUT request to $url with token: $token');

    try {
      final response = await _client.put(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      print('Response status: ${response.statusCode}, body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Failed to mark messages as seen: ${response.body}');
      }

      // Return the response data if needed
      final data = jsonDecode(response.body);
      print('Marked ${data['count']} messages as seen');
    } catch (e) {
      print('Error marking messages as seen: $e');
      throw e;
    }
  }
}
