import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../providers/api_service.dart';
import '../providers/auth_provider.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  ProfilePageState createState() => ProfilePageState();
}

class ProfilePageState extends State<ProfilePage> {
  bool isHardwareConnected = false;
  List<FlSpot> bloodPressureData = [];
  List<Map<String, dynamic>> weeklyReadings = [];
  Map<String, dynamic>? userData;
  Map<String, dynamic>? companionData;
  Map<String, dynamic>? doctorData;
  List<dynamic> nearbyLocations = [];
  late WebViewController _webViewController;
  bool _isMapLoading = true;
  String lastBeatTime = '';
  bool isMeasurementActive = false;
  int beatsDetected = 0;
  double currentBpm = 0;
  double currentSpO2 = 0;
  Position? currentPosition;
  Timer? _beatTimer;
  int unseenMessageCount = 0;
  bool _hasError = false;
  String _errorMessage = '';
  DateTime? selectedDate;
  List<String> datesWithData = [];
  List<Map<String, dynamic>> selectedDateReadings = [];

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isLoggedIn || authProvider.token == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/login');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Please log in to access your profile.')),
        );
      });
      return;
    }
    _checkEspHealth();
    _getCurrentLocation();
    loadData();
    startBeatPolling();

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _isMapLoading = true;
            });
          },
          onPageFinished: (url) {
            setState(() {
              _isMapLoading = false;
            });
          },
        ),
      );
  }

  @override
  void dispose() {
    _beatTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkEspHealth() async {
    final isConnected = await ApiService().checkEspHealth();
    setState(() {
      isHardwareConnected = isConnected;
    });
  }

  Future<void> _updateMapLocation() async {
    if (currentPosition == null) return;

    final lat = currentPosition!.latitude;
    final lng = currentPosition!.longitude;

    final double offset = 0.01;
    final String bbox = '${lng - offset}%2C${lat - offset}%2C${lng + offset}%2C${lat + offset}';

    final String mapUrl = 'https://www.openstreetmap.org/export/embed.html?bbox=$bbox&layer=mapnik&marker=$lat%2C$lng';

    await _webViewController.loadRequest(Uri.parse(mapUrl));
  }

  Future<void> _showNearbyLocationsOnMap() async {
    if (currentPosition == null || nearbyLocations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No nearby locations available')),
      );
      return;
    }

    final lat = currentPosition!.latitude;
    final lng = currentPosition!.longitude;

    double minLat = lat;
    double maxLat = lat;
    double minLng = lng;
    double maxLng = lng;

    for (final location in nearbyLocations) {
      final locLat = location['latitude'] as double;
      final locLng = location['longitude'] as double;

      minLat = min(minLat, locLat);
      maxLat = max(maxLat, locLat);
      minLng = min(minLng, locLng);
      maxLng = max(maxLng, locLng);
    }

    final double padding = 0.005;
    minLat -= padding;
    maxLat += padding;
    minLng -= padding;
    maxLng += padding;

    final List<String> markers = [];
    markers.add('$lat,$lng');

    for (final location in nearbyLocations) {
      final locLat = location['latitude'] as double;
      final locLng = location['longitude'] as double;
      markers.add('$locLat,$locLng');
    }

    final String markersParam = markers.join('&marker=');
    final String bbox = '$minLng%2C$minLat%2C$maxLng%2C$maxLat';

    final String mapUrl = 'https://www.openstreetmap.org/export/embed.html?bbox=$bbox&layer=mapnik&marker=$markersParam';

    await _webViewController.loadRequest(Uri.parse(mapUrl));
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Location services are disabled. Please enable them.')),
      );
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are denied.')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Location permissions are permanently denied.')),
      );
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        currentPosition = position;
      });
      _updateMapLocation();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: $e')),
      );
    }
  }

  Future<void> loadData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token ?? '';
    if (token.isEmpty) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Session expired. Please log in again.')),
        );
      }
      return;
    }

    try {
      final user = await ApiService().getUserProfile(token);
      setState(() {
        userData = user;
      });

      if (user['role'] == 'Patient' && user['companionId'] != null) {
        final companion =
            await ApiService().getCompanion(token, user['companionId']);
        setState(() {
          companionData = companion;
        });
      }

      if (user['role'] == 'Patient' && user['doctorId'] != null) {
        final doctor = await ApiService().getCompanion(token, user['doctorId']);
        setState(() {
          doctorData = doctor;
        });
      }

      final latitude = currentPosition?.latitude ?? 30.033333;
      final longitude = currentPosition?.longitude ?? 31.233334;
      final locations =
          await ApiService().getNearbyLocations(token, latitude, longitude);
      setState(() {
        nearbyLocations = locations;
      });

      try {
        final count = await ApiService().getUnseenMessageCount(token);
        setState(() {
          unseenMessageCount = count;
        });
      } catch (e) {
        print('Failed to fetch unseen message count: $e');
        setState(() {
          unseenMessageCount = 0;
        });
      }

      final dates = await ApiService().getReadingDates(token);
      setState(() {
        datesWithData = dates;
      });

      final now = DateTime.now();
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 6));
      final readings =
          await ApiService().getReadings(token, startOfWeek, endOfWeek);
      setState(() {
        weeklyReadings = readings;
        bloodPressureData = _generateWeeklyData(readings);
      });

      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      if (dates.contains(todayStr)) {
        await _loadReadingsForDate(now);
      }
    } catch (e) {
      if (e.toString().contains('Unauthorized') ||
          e.toString().contains('Token is not valid') ||
          e.toString().contains('401')) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Session expired. Please log in again.')),
          );
        }
      } else {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $e')),
        );
      }
    }
  }

  List<FlSpot> _generateWeeklyData(List<Map<String, dynamic>> readings) {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final Map<int, List<Map<String, dynamic>>> dailyReadings = {};

    for (var reading in readings) {
      final timestamp = DateTime.parse(reading['timestamp']);
      final dayOffset = timestamp.difference(startOfWeek).inDays;
      if (dayOffset >= 0 && dayOffset < 7) {
        dailyReadings[dayOffset] ??= [];
        dailyReadings[dayOffset]!.add(reading);
      }
    }

    List<FlSpot> spots = [];
    for (int day = 0; day < 7; day++) {
      final dayReadings = dailyReadings[day] ?? [];
      if (dayReadings.isEmpty) {
        spots.add(FlSpot(day.toDouble(), 0));
        continue;
      }

      double avgHeartRate = 0;
      if (dayReadings.length <= 3) {
        avgHeartRate = dayReadings
                .map((r) => r['heartRate'] as num)
                .reduce((a, b) => a + b) /
            dayReadings.length;
      } else {
        avgHeartRate = dayReadings
                .map((r) => r['heartRate'] as num)
                .reduce((a, b) => a + b) /
            dayReadings.length;
      }
      spots.add(FlSpot(day.toDouble(), avgHeartRate));
    }
    return spots;
  }

  Future<void> _loadReadingsForDate(DateTime date) async {
    setState(() {
      selectedDate = date;
      selectedDateReadings = [];
    });

    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token ?? '';
    if (token.isEmpty) return;

    try {
      final readings =
          await ApiService().getReadings(token, startOfDay, endOfDay);
      setState(() {
        selectedDateReadings = readings;
        if (readings.isNotEmpty) {
          currentBpm = readings.last['heartRate'];
          currentSpO2 = readings.last['spo2'];
        }
      });
    } catch (e) {
      print('Error loading readings for date: $e');
    }
  }

  void startBeatPolling() {
    _beatTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      try {
        final beatData = await ApiService().getBeatData();
        setState(() {
          if (beatData['lastBeatTime'] != null &&
              beatData['lastBeatTime'] != lastBeatTime) {
            lastBeatTime = beatData['lastBeatTime'];
          }
          isMeasurementActive = beatData['measurementActive'];
          beatsDetected = beatData['beatsDetected'];
        });
      } catch (e) {
        print('Error polling beat data: $e');
      }
    });
  }

  Future<void> startReading() async {
    if (!isHardwareConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device not connected')),
      );
      return;
    }

    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Location not available. Please enable location services.')),
      );
      return;
    }

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token ?? '';
      if (token.isEmpty) return;

      final reading = await ApiService().startReading(
          token, currentPosition!.latitude, currentPosition!.longitude);
      setState(() {
        currentBpm = reading['heartRate'];
        currentSpO2 = reading['spo2'];
      });

      if (selectedDate != null) {
        await _loadReadingsForDate(selectedDate!);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting reading: $e')),
      );
    }
  }

  Future<void> _sendNotification(
      String recipientId, String recipientName) async {
    if (currentBpm == 0 || currentSpO2 == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No recent reading available to send')),
      );
      return;
    }

    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Location not available. Please enable location services.')),
      );
      return;
    }

    final messageContent =
        'Heartbeat: ${currentBpm.toStringAsFixed(1)} BPM, SpO2: ${currentSpO2.toStringAsFixed(1)}%, Location: (${currentPosition!.latitude}, ${currentPosition!.longitude})';
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token ?? '';
    if (token.isEmpty) return;

    try {
      final url = '${ApiService.baseUrl}/messages';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'recipientId': recipientId,
          'content': messageContent,
        }),
      );

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Notification sent to $recipientName')),
        );
      } else {
        throw Exception('Failed to send notification: ${response.body}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending notification: $e')),
      );
    }
  }

  Future<void> _sendLocationOnly(String recipientId, String recipientName) async {
    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Location not available. Please enable location services.')),
      );
      return;
    }

    final messageContent =
        'My current location: (${currentPosition!.latitude}, ${currentPosition!.longitude})';
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token ?? '';
    if (token.isEmpty) return;

    try {
      final url = '${ApiService.baseUrl}/messages';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'recipientId': recipientId,
          'content': messageContent,
        }),
      );

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location sent to $recipientName')),
        );
      } else {
        throw Exception('Failed to send location: ${response.body}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending location: $e')),
      );
    }
  }

  void _openChat(String recipientId, String recipientName) {
    Navigator.pushNamed(
      context,
      '/chat',
      arguments: {
        'recipientId': recipientId,
        'recipientName': recipientName,
      },
    );
  }

  int calculateAge(String birthdate) {
    DateTime birthDate = DateTime.parse(birthdate);
    DateTime today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text(
          'Profile',
          style: TextStyle(color: Colors.white, fontSize: 24),
        ),
        leading: IconButton(
          icon: const Icon(Icons.logout, color: Colors.white, size: 30),
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text(
                  'Sign Out',
                  style: TextStyle(fontSize: 22),
                ),
                content: const Text(
                  'Are you sure you want to sign out?',
                  style: TextStyle(fontSize: 18),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Provider.of<AuthProvider>(context, listen: false).logout();
                      Navigator.pushReplacementNamed(context, '/login');
                    },
                    child: const Text(
                      'Sign Out',
                      style: TextStyle(fontSize: 16, color: Colors.red),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.message, color: Colors.white, size: 30),
                onPressed: () {
                  Navigator.pushNamed(context, '/user_selection');
                },
              ),
              if (unseenMessageCount > 0)
                Positioned(
                  right: 5,
                  top: 5,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$unseenMessageCount',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _hasError
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Failed to load profile: $_errorMessage',
                    style: const TextStyle(fontSize: 18, color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _hasError = false;
                        _errorMessage = '';
                      });
                      loadData();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : userData == null
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(context, '/device_manager');
                        },
                        child: Row(
                          children: [
                            Stack(
                              alignment: Alignment.topRight,
                              children: [
                                const Icon(
                                  Icons.memory,
                                  size: 40,
                                  color: Colors.black54,
                                ),
                                Container(
                                  width: 15,
                                  height: 15,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isHardwareConnected
                                        ? Colors.green
                                        : Colors.red,
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Text(
                              isHardwareConnected
                                  ? 'Connected'
                                  : 'Not Connected',
                              style: TextStyle(
                                fontSize: 22,
                                color: isHardwareConnected
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (userData!['role'] == 'Patient') ...[
                        if (companionData != null) ...[
                          const Text(
                            'Companion Information',
                            style: TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.person,
                                    color: Colors.blue, size: 40),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        companionData!['name'] ?? 'Unknown',
                                        style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        'Phone: ${companionData!['phoneNumber'] ?? 'N/A'}',
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.notification_important,
                                    color: Colors.red,
                                    size: 28,
                                  ),
                                  onPressed: () {
                                    _sendNotification(companionData!['_id'],
                                        companionData!['name']);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (doctorData != null) ...[
                          const Text(
                            'Doctor Information',
                            style: TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.medical_services,
                                    color: Colors.blue, size: 40),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        doctorData!['name'] ?? 'Unknown',
                                        style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        'Phone: ${doctorData!['phoneNumber'] ?? 'N/A'}',
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.notification_important,
                                    color: Colors.red,
                                    size: 28,
                                  ),
                                  onPressed: () {
                                    _sendNotification(doctorData!['_id'],
                                        doctorData!['name']);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ],
                      const Text(
                        'Select Date for Readings',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: () async {
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                            selectableDayPredicate: (DateTime date) {
                              final dateStr =
                                  DateFormat('yyyy-MM-dd').format(date);
                              return datesWithData.contains(dateStr);
                            },
                            builder: (context, child) {
                              return Theme(
                                data: ThemeData.light().copyWith(
                                  colorScheme: const ColorScheme.light(
                                    primary: Colors.blue,
                                    onPrimary: Colors.white,
                                    surface: Colors.white,
                                    onSurface: Colors.black,
                                  ),
                                  dialogBackgroundColor: Colors.white,
                                  textButtonTheme: TextButtonThemeData(
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.blue,
                                    ),
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (pickedDate != null) {
                            await _loadReadingsForDate(pickedDate);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          selectedDate == null
                              ? 'Select Date'
                              : 'Selected: ${DateFormat('yyyy-MM-dd').format(selectedDate!)}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Live Heartbeat Monitor',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              transform:
                                  lastBeatTime.isNotEmpty && isMeasurementActive
                                      ? (Matrix4.identity()..scale(1.3))
                                      : Matrix4.identity(),
                              onEnd: () {
                                if (lastBeatTime.isNotEmpty &&
                                    isMeasurementActive) {
                                  setState(() {
                                    lastBeatTime = '';
                                  });
                                }
                              },
                              child: const Icon(
                                Icons.favorite,
                                color: Colors.red,
                                size: 40,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isMeasurementActive
                                        ? 'Measuring... ($beatsDetected beats)'
                                        : 'Measurement Complete',
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                  if (currentBpm > 0)
                                    Text(
                                      'BPM: ${currentBpm.toStringAsFixed(1)}',
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  if(currentSpO2 > 0)
                                    Text(
                                      'SpO2: ${currentSpO2.toStringAsFixed(1)}%',
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (selectedDate != null &&
                          selectedDateReadings.isNotEmpty) ...[
                        const Text(
                          'Readings for Selected Date',
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        ...selectedDateReadings.map((reading) {
                          final timestamp =
                              DateTime.parse(reading['timestamp']);
                          return ListTile(
                            title: Text(
                                'BPM: ${reading['heartRate'].toStringAsFixed(1)}'),
                            subtitle: Text(
                              'SpO2: ${reading['spo2'].toStringAsFixed(1)}% | Time: ${DateFormat('HH:mm').format(timestamp)}',
                            ),
                          );
                        }).toList(),
                        const SizedBox(height: 20),
                      ],
                      if (userData!['role'] == 'Patient') ...[
                        const Text(
                          'Weekly Heart Rate Analysis',
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: 200,
                          padding: const EdgeInsets.all(16),
                          child: LineChart(
                            LineChartData(
                              gridData: const FlGridData(show: false),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      final day = value.toInt();
                                      final date = DateTime.now().subtract(
                                          Duration(
                                              days: DateTime.now().weekday -
                                                  1 -
                                                  day));
                                      return Text(
                                        DateFormat('E').format(date),
                                        style: const TextStyle(fontSize: 12),
                                      );
                                    },
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      return Text(
                                        '${value.toInt()} BPM',
                                        style: const TextStyle(fontSize: 10),
                                      );
                                    },
                                    reservedSize: 50,
                                  ),
                                ),
                                topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                              ),
                              borderData: FlBorderData(show: false),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: bloodPressureData,
                                  isCurved: true,
                                  color: Colors.blue,
                                  dotData: const FlDotData(show: false),
                                  belowBarData: BarAreaData(show: false),
                                ),
                              ],
                              minX: 0,
                              maxX: 6,
                              minY: 0,
                              maxY: 150,
                            ),
                          ),
                        ).animate().fadeIn(duration: 1000.ms).scale(),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pushNamed(context, '/view_analysis');
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'View Analysis',
                                style: TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: startReading,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Read Now',
                                style: TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (userData != null &&
                          (companionData != null || doctorData != null)) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'My Companions',
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        if (userData!['role'] == 'Patient' &&
                            companionData != null)
                          Card(
                            elevation: 4,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const CircleAvatar(
                                        backgroundColor: Colors.blue,
                                        child: Icon(Icons.person,
                                            color: Colors.white),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              companionData!['name'] ??
                                                  'Companion',
                                              style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                            Text(
                                              'Role: ${companionData!['role'] ?? 'Companion'}',
                                              style:
                                                  const TextStyle(fontSize: 14),
                                            ),
                                            if (companionData!['phoneNumber'] !=
                                                null)
                                              Text(
                                                'Phone: ${companionData!['phoneNumber']}',
                                                style:
                                                    const TextStyle(fontSize: 14),
                                              ),
                                            if (companionData!['email'] != null)
                                              Text(
                                                'Email: ${companionData!['email']}',
                                                style:
                                                    const TextStyle(fontSize: 14),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.message),
                                        label: const Text('Chat'),
                                        onPressed: () {
                                          _openChat(companionData!['_id'],
                                              companionData!['name']);
                                        },
                                      ),
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.notifications),
                                        label: const Text('Alert'),
                                        onPressed: () {
                                          _sendNotification(
                                              companionData!['_id'],
                                              companionData!['name']);
                                        },
                                      ),
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.location_on),
                                        label: const Text('Location'),
                                        onPressed: () {
                                          _sendLocationOnly(
                                              companionData!['_id'],
                                              companionData!['name']);
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (userData!['role'] == 'Patient' && doctorData != null)
                          Card(
                            elevation: 4,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const CircleAvatar(
                                        backgroundColor: Colors.green,
                                        child: Icon(Icons.medical_services,
                                            color: Colors.white),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              doctorData!['name'] ?? 'Doctor',
                                              style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                            Text(
                                              'Role: ${doctorData!['role'] ?? 'Doctor'}',
                                              style:
                                                  const TextStyle(fontSize: 14),
                                            ),
                                            if (doctorData!['phoneNumber'] != null)
                                              Text(
                                                'Phone: ${doctorData!['phoneNumber']}',
                                                style:
                                                    const TextStyle(fontSize: 14),
                                              ),
                                            if (doctorData!['email'] != null)
                                              Text(
                                                'Email: ${doctorData!['email']}',
                                                style:
                                                    const TextStyle(fontSize: 14),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.message),
                                        label: const Text('Chat'),
                                        onPressed: () {
                                          _openChat(doctorData!['_id'],
                                              doctorData!['name']);
                                        },
                                      ),
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.notifications),
                                        label: const Text('Alert'),
                                        onPressed: () {
                                          _sendNotification(doctorData!['_id'],
                                              doctorData!['name']);
                                        },
                                      ),
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.location_on),
                                        label: const Text('Location'),
                                        onPressed: () {
                                          _sendLocationOnly(doctorData!['_id'],
                                              doctorData!['name']);
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: Text(
                          'My Location',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Card(
                        elevation: 4,
                        child: Column(
                          children: [
                            SizedBox(
                              height: 300,
                              child: Stack(
                                children: [
                                  WebViewWidget(controller: _webViewController),
                                  if (_isMapLoading)
                                    const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  Positioned(
                                    bottom: 16,
                                    right: 16,
                                    child: Column(
                                      children: [
                                        FloatingActionButton(
                                          heroTag: "recenterBtn",
                                          mini: true,
                                          backgroundColor: Colors.white,
                                          onPressed: () {
                                            _updateMapLocation();
                                          },
                                          child: const Icon(
                                            Icons.my_location,
                                            color: Colors.blue,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        FloatingActionButton(
                                          heroTag: "nearbyBtn",
                                          mini: true,
                                          backgroundColor: Colors.white,
                                          onPressed: () {
                                            _showNearbyLocationsOnMap();
                                          },
                                          child: const Icon(
                                            Icons.local_pharmacy,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                currentPosition != null
                                    ? 'Lat: ${currentPosition!.latitude.toStringAsFixed(6)}, Lng: ${currentPosition!.longitude.toStringAsFixed(6)}'
                                    : 'Location not available',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Table(
                        border: TableBorder.all(color: Colors.grey[300]!),
                        children: [
                          const TableRow(
                            children: [
                              Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Text(
                                  'Name',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Text(
                                  'Type',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Text(
                                  'Distance',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          ...nearbyLocations.map((location) {
                            final latitude =
                                currentPosition?.latitude ?? 30.033333;
                            final longitude =
                                currentPosition?.longitude ?? 31.233334;
                            final distance = _calculateDistance(
                              latitude,
                              longitude,
                              location['coordinates']['latitude'],
                              location['coordinates']['longitude'],
                            );
                            return TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    location['name'],
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    location['type'],
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    '${distance.toStringAsFixed(1)} km',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (userData != null) ...[
                        Card(
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Profile Information',
                                      style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.edit),
                                      label: const Text('Edit'),
                                      onPressed: () {
                                        Navigator.pushNamed(
                                          context,
                                          '/edit_profile',
                                          arguments: {'userData': userData},
                                        ).then((_) => loadData());
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Name: ${userData!['name'] ?? 'N/A'}',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                Text(
                                  'Email: ${userData!['email'] ?? 'N/A'}',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                if (userData!['phoneNumber'] != null)
                                  Text(
                                    'Phone: ${userData!['phoneNumber']}',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                if (userData!['birthdate'] != null)
                                  Text(
                                    'Age: ${calculateAge(userData!['birthdate'])}',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                Text(
                                  'Role: ${userData!['role'] ?? 'N/A'}',
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double kmPerLatDegree = 111.0;
    const double kmPerLonDegree = 111.0 * 0.85;
    final latDiff = (lat2 - lat1) * kmPerLatDegree;
    final lonDiff = (lon2 - lon1) * kmPerLonDegree;
    return sqrt(latDiff * latDiff + lonDiff * lonDiff);
  }
}