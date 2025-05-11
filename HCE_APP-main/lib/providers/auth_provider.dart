import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../main.dart';

class AuthProvider with ChangeNotifier {
  static const String _baseUrl = AppConfig.baseUrl; // Base URL for API
  static const String _authUrl = '$_baseUrl/auth'; // URL for auth endpoints
  static const String _tokenKey = 'token';
  static String _espIpKey = 'esp_ip'; // Changed from const and using a string literal

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
  
  // New getter that safely returns the user role for debugging
  String get userRole {
    if (_role != null) return _role!;
    if (_userProfile != null && _userProfile!['role'] != null) {
      return _userProfile!['role']!;
    }
    return 'unknown';
  }

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
        
        // Extract relationship phone numbers if available
        if (_userProfile != null) {
          if (_userProfile!['role'] == 'Patient') {
            // For patient, get doctor and companion phone numbers
            await _getRelationshipPhoneNumbers();
          } else if (_userProfile!['role'] == 'Companion') {
            // For companion, get patient phone number
            await _getPatientPhoneNumber();
          }
        }
        
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
  
  // Get phone numbers for patient's doctor and companion
  Future<void> _getRelationshipPhoneNumbers() async {
    try {
      if (_userProfile == null || _token == null) return;
      
      // Get doctor phone number if doctorId exists
      if (_userProfile!['doctorId'] != null) {
        final doctorResponse = await http.get(
          Uri.parse('$_baseUrl/users/${_userProfile!['doctorId']}'),
          headers: {'Authorization': 'Bearer $_token'},
        );
        
        if (doctorResponse.statusCode == 200) {
          final doctorData = json.decode(doctorResponse.body);
          _userProfile!['doctorPhoneNumber'] = doctorData['phoneNumber'];
        }
      }
      
      // Get companion phone number if companionId exists
      if (_userProfile!['companionId'] != null) {
        final companionResponse = await http.get(
          Uri.parse('$_baseUrl/users/${_userProfile!['companionId']}'),
          headers: {'Authorization': 'Bearer $_token'},
        );
        
        if (companionResponse.statusCode == 200) {
          final companionData = json.decode(companionResponse.body);
          _userProfile!['companionPhoneNumber'] = companionData['phoneNumber'];
        }
      }
    } catch (e) {
      debugPrint('Error getting relationship phone numbers: $e');
    }
  }
  
  // Get phone number for companion's patient
  Future<void> _getPatientPhoneNumber() async {
    try {
      if (_userProfile == null || _token == null) return;
      
      // Get patient phone number if patientId exists
      if (_userProfile!['patientId'] != null) {
        final patientResponse = await http.get(
          Uri.parse('$_baseUrl/users/${_userProfile!['patientId']}'),
          headers: {'Authorization': 'Bearer $_token'},
        );
        
        if (patientResponse.statusCode == 200) {
          final patientData = json.decode(patientResponse.body);
          _userProfile!['patientPhoneNumber'] = patientData['phoneNumber'];
        }
      }
    } catch (e) {
      debugPrint('Error getting patient phone number: $e');
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
    String? doctorPhoneNumber,
  }) async {
    try {
      final payload = {
        'name': name,
        'email': email.trim(),
        'password': password,
        'phoneNumber': phoneNumber.trim(),
        'birthdate': birthdate,
        'role': role,
      };
      
      // Add optional fields based on role
      if (role == 'Patient') {
        if (bloodPressureType != null) {
          payload['bloodPressureType'] = bloodPressureType;
        }
        if (companionPhoneNumber != null && companionPhoneNumber.isNotEmpty) {
          payload['companionPhoneNumber'] = companionPhoneNumber.trim();
        }
        if (doctorPhoneNumber != null && doctorPhoneNumber.isNotEmpty) {
          payload['doctorPhoneNumber'] = doctorPhoneNumber.trim();
        }
      } else if (role == 'Companion') {
        if (patientPhoneNumber != null && patientPhoneNumber.isNotEmpty) {
          payload['patientPhoneNumber'] = patientPhoneNumber.trim();
        }
      }
      
      final response = await http.post(
        Uri.parse('$_authUrl/signup'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );

      final result = await _handleAuthResponse(response);
      
      // If signup was successful and we have relationship data, update the relationships
      if (result['success'] && _token != null) {
        // We're already logged in, so we can update relationships if needed
        final updateData = <String, dynamic>{};
        
        if (role == 'Patient') {
          if (companionPhoneNumber != null && companionPhoneNumber.isNotEmpty) {
            updateData['companionPhoneNumber'] = companionPhoneNumber.trim();
          }
          if (doctorPhoneNumber != null && doctorPhoneNumber.isNotEmpty) {
            updateData['doctorPhoneNumber'] = doctorPhoneNumber.trim();
          }
        } else if (role == 'Companion') {
          if (patientPhoneNumber != null && patientPhoneNumber.isNotEmpty) {
            updateData['patientPhoneNumber'] = patientPhoneNumber.trim();
          }
        }
        
        // If we have relationship data to update, make the update request
        if (updateData.isNotEmpty) {
          try {
            await updateProfile(updateData);
          } catch (e) {
            debugPrint('Error updating relationships after signup: $e');
            // We don't want to fail the signup if relationship update fails
          }
        }
      }
      
      return result;
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
  
  // Update user profile
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> updateData) async {
    if (_token == null || _userId == null) {
      return {'success': false, 'message': 'Not authenticated'};
    }
    
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/users/$_userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token'
        },
        body: json.encode(updateData),
      );
      
      if (response.statusCode == 200) {
        // Refresh user profile after update
        await fetchUserProfile();
        return {'success': true};
      } else {
        final data = json.decode(response.body);
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to update profile'
        };
      }
    } catch (e) {
      debugPrint('Error updating profile: $e');
      return {
        'success': false,
        'message': 'Network error occurred. Please try again.'
      };
    }
  }
}