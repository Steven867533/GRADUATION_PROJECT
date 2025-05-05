import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

class AuthProvider with ChangeNotifier {
  static const String _baseUrl = 'http://10.0.2.2:5000'; // Base URL for API
  static const String _authUrl = '$_baseUrl/auth'; // URL for auth endpoints
  static const String _tokenKey = 'token';
  static const String _espIpKey = 'http://10.0.2.2:5001'; // Key for ESP IP

  String? _token;
  String? _userId;
  String? _role;
  Map<String, dynamic>? _userProfile;
  String? _espIp; // Store ESP IP

  // Getters
  bool get isLoggedIn => _token != null && !JwtDecoder.isExpired(_token!);
  String? get token => _token;
  String? get userId => _userId;
  String? get role => _role;
  Map<String, dynamic>? get userProfile => _userProfile;
  String? get espIp => _espIp;

  AuthProvider() {
    _loadToken();
    _loadEspIp();
  }

  Future<void> _loadToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_tokenKey);

      if (_token != null) {
        if (JwtDecoder.isExpired(_token!)) {
          await logout();
          return;
        }

        final decodedToken = JwtDecoder.decode(_token!);
        _userId = decodedToken['userId']?.toString();
        _role = decodedToken['role']?.toString();
        await fetchUserProfile();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading token: $e');
      await logout();
    }
  }

  // Load ESP IP
  Future<void> _loadEspIp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _espIp = prefs.getString(_espIpKey);
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading ESP IP: $e');
    }
  }

  // Save ESP IP
  Future<void> saveEspIp(String ip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_espIpKey, ip);
      _espIp = ip;
      notifyListeners();
    } catch (e) {
      debugPrint('Error saving ESP IP: $e');
      throw Exception('Failed to save ESP IP');
    }
  }

  // Clear ESP IP
  Future<void> clearEspIp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_espIpKey);
      _espIp = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Error clearing ESP IP: $e');
    }
  }

  // Fetch user profile
  Future<void> fetchUserProfile() async {
    if (_token == null) {
      _userProfile = null;
      notifyListeners();
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/users/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
          'Screen': 'auth_provider'
        },
      );

      if (response.statusCode == 200) {
        _userProfile = json.decode(response.body);
        notifyListeners();
      } else {
        final data = json.decode(response.body);
        debugPrint('Error fetching user profile: ${data['message']}');
        _userProfile = null;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Network error fetching user profile: $e');
      _userProfile = null;
      notifyListeners();
    }
  }

  // Save token
  Future<void> _saveToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);

      _token = token;
      final decodedToken = JwtDecoder.decode(token);
      _userId = decodedToken['userId']?.toString();
      _role = decodedToken['role']?.toString();
      await fetchUserProfile();
      notifyListeners();
    } catch (e) {
      debugPrint('Error saving token: $e');
      throw Exception('Failed to save credentials');
    }
  }

  // Clear credentials
  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);

      _token = null;
      _userId = null;
      _role = null;
      _userProfile = null;
      await clearEspIp();
      notifyListeners();
    } catch (e) {
      debugPrint('Error during logout: $e');
      throw Exception('Failed to logout');
    }
  }

  // Handle API response
  Future<Map<String, dynamic>> _handleAuthResponse(
      http.Response response) async {
    try {
      final data = json.decode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final token = data['token'];
        if (token == null) {
          return {'success': false, 'message': 'Token not found in response'};
        }

        await _saveToken(token);
        return {'success': true};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Authentication failed'
        };
      }
    } catch (e) {
      debugPrint('Error handling auth response: $e');
      return {'success': false, 'message': 'Failed to process response'};
    }
  }

  // Sign up method
  Future<Map<String, dynamic>> signUp({
    required String name,
    required String email,
    required String password,
    required String phoneNumber,
    required String birthdate,
    required String role,
    String? bloodPressureType,
    String? patientPhoneNumber,
    String? companionPhoneNumber,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_authUrl/signup'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'email': email.trim(),
          'password': password,
          'phoneNumber': phoneNumber.trim(),
          'birthdate': birthdate,
          'role': role,
          if (bloodPressureType != null) 
            'bloodPressureType': bloodPressureType,
          if (patientPhoneNumber != null)
            'patientPhoneNumber': patientPhoneNumber.trim(),
          if (companionPhoneNumber != null)
            'companionPhoneNumber': companionPhoneNumber.trim(),
        }),
      );

      return await _handleAuthResponse(response);
    } catch (e) {
      debugPrint('Error during signup: $e');
      return {
        'success': false,
        'message': 'Network error occurred. Please try again.'
      };
    }
  }

  // Login method
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_authUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email.trim(),
          'password': password,
        }),
      );

      return await _handleAuthResponse(response);
    } catch (e) {
      debugPrint('Error during login: $e');
      return {
        'success': false,
        'message': 'Network error occurred. Please try again.'
      };
    }
  }
}