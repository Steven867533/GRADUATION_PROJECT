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
import 'package:web_socket_channel/web_socket_channel.dart';
import './view_analysis_page.dart';

// Static class to maintain WebSocket state across navigations
class WebSocketManager {
  static WebSocketChannel? _channel;
  static bool isConnected = false;
  static bool isConnecting = false;
  static String? lastUrl;
  static StreamSubscription? _subscription;
  static Stream<dynamic>? _broadcastStream;
  static Timer? _pingTimer;
  static bool _waitingForPong = false;
  static DateTime? _lastPongTime;

  // Add safety flag for controlled dispose process
  static bool safeToDispose = false;

  // Add flag for explicitly requested disposal during signout
  static bool disposalRequested = false;

  // Add new method to check connection status with the ESP
  static Future<bool> checkConnectionStatus() async {
    if (_channel == null) return false;

    try {
      // Send a ping and set waiting flag
      final pingMessage = jsonEncode({'command': 'ping'});
      sendMessage(pingMessage);

      _waitingForPong = true;

      // Wait for response for up to 3 seconds
      for (int i = 0; i < 6; i++) {
        await Future.delayed(const Duration(milliseconds: 500));

        // If we received a pong while waiting
        if (!_waitingForPong ||
            (_lastPongTime != null &&
                DateTime.now().difference(_lastPongTime!).inSeconds < 3)) {
          return true;
        }
      }

      // If we get here, no pong was received
      print('No pong received within timeout, connection appears to be dead');
      isConnected = false;
      return false;
    } catch (e) {
      print('WebSocket connection check failed: $e');
      isConnected = false;
      return false;
    }
  }

  // Method to handle pong responses
  static void handlePong() {
    _waitingForPong = false;
    _lastPongTime = DateTime.now();
    isConnected = true;
  }

  // Start periodic ping to keep connection alive
  static void startPingTimer() {
    stopPingTimer();

    _pingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_channel != null && isConnected) {
        print('Sending periodic ping to keep connection alive');
        final pingMessage = jsonEncode({'command': 'ping'});
        sendMessage(pingMessage);
      } else {
        // If connection is lost, stop pinging
        stopPingTimer();
      }
    });
  }

  // Stop ping timer
  static void stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  static WebSocketChannel? get channel => _channel;

  static void setChannel(WebSocketChannel? channel, String url) {
    // Clean up existing subscription if any
    if (_subscription != null) {
      _subscription!.cancel();
      _subscription = null;
    }

    _channel = channel;
    lastUrl = url;
    isConnected = channel != null;

    // Create a broadcast stream from the channel stream to allow multiple listeners
    if (_channel != null) {
      _broadcastStream = _channel!.stream.asBroadcastStream();

      // Start ping timer to keep connection alive
      startPingTimer();
    } else {
      _broadcastStream = null;
      stopPingTimer();
    }
  }

  // Centralized dispose method that respects safety flags
  static void safeDispose() {
    if (!safeToDispose && !disposalRequested) {
      print(
          "WebSocketManager: Skipping disposal as it's not safe to dispose yet");
      return;
    }

    print("WebSocketManager: Safe dispose initiated");
    stopPingTimer();

    if (_subscription != null) {
      _subscription!.cancel();
      _subscription = null;
    }

    _channel?.sink.close();
    _channel = null;
    _broadcastStream = null;
    isConnected = false;
    isConnecting = false;

    // Reset the flag after disposal
    disposalRequested = false;
  }

  // Request disposal (to be used during signout)
  static void requestDispose() {
    disposalRequested = true;
    safeDispose();
  }

  // Original disconnect method now uses the safe dispose
  static void disconnect() {
    safeDispose();
  }

  static void setupListener(void Function(dynamic) onMessage,
      void Function() onDone, void Function(dynamic) onError) {
    // Cancel existing subscription if any
    if (_subscription != null) {
      _subscription!.cancel();
      _subscription = null;
    }

    if (_channel != null && _broadcastStream != null) {
      _subscription =
          _broadcastStream!.listen(onMessage, onDone: onDone, onError: onError);
    }
  }

  // Send a message to the WebSocket
  static void sendMessage(String message) {
    if (_channel != null && isConnected) {
      _channel!.sink.add(message);
    }
  }
}

// Add static resource manager class to ensure safe disposal
class ResourceManager {
  static final Map<String, bool> _resourceState = {};
  static bool _safeToDisposeAll = false;

  // Register a resource
  static void register(String resourceName) {
    _resourceState[resourceName] = true;
    print('ResourceManager: Registered $resourceName');
  }

  // Unregister a resource
  static void unregister(String resourceName) {
    _resourceState.remove(resourceName);
    print('ResourceManager: Unregistered $resourceName');
  }

  // Check if it's safe to dispose a specific resource
  static bool isSafeToDispose(String resourceName) {
    return _safeToDisposeAll || !_resourceState.containsKey(resourceName);
  }

  // Mark all as safe to dispose (during page reload/signout)
  static void markAllSafeToDispose() {
    _safeToDisposeAll = true;
    print('ResourceManager: All resources marked safe to dispose');
  }

  // Reset safe dispose flag
  static void resetSafeDispose() {
    _safeToDisposeAll = false;
    print('ResourceManager: Safe dispose flag reset');
  }

  // Dispose all resources
  static void disposeAll() {
    markAllSafeToDispose();
    WebSocketManager.safeToDispose = true;
    WebSocketManager.safeDispose();
    _resourceState.clear();
  }
}

// Create a safe setState extension
extension SafeSetState<T extends StatefulWidget> on State<T> {
  void safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    } else {
      print('SafeSetState: Avoided setState on unmounted widget');
    }
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  ProfilePageState createState() => ProfilePageState();
}

class ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  // Add a unique ID for this instance
  final String _instanceId = DateTime.now().millisecondsSinceEpoch.toString();

  // Add a key for forcing rebuild
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // State variables for companion-patient relationship
  Map<String, dynamic>? patientData;
  String? patientId;

  // Static method to reload page by pushing a fresh instance
  static void reloadPage(BuildContext context) {
    // Mark all resources as safe to dispose
    ResourceManager.markAllSafeToDispose();
    WebSocketManager.safeToDispose = true;

    // Push a completely fresh instance that replaces the current page
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const ProfilePage()),
    ).then((_) {
      // Reset safe dispose flag after navigation
      ResourceManager.resetSafeDispose();
      WebSocketManager.safeToDispose = false;
    });
  }

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
  bool _isConnectingWebSocket = false;
  bool _isWebSocketConnected = false;
  late AnimationController _heartAnimationController;
  double _heartScale = 1.0;

  @override
  void initState() {
    super.initState();

    // Register this instance with the resource manager
    ResourceManager.register(_instanceId);

    // Initialize UI controllers first
    _heartAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _heartAnimationController.addListener(() {
      safeSetState(() {
        _heartScale = 1.0 + (_heartAnimationController.value * 0.3);
      });
    });

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            safeSetState(() {
              _isMapLoading = true;
            });
          },
          onPageFinished: (url) {
            safeSetState(() {
              _isMapLoading = false;
            });
          },
        ),
      );

    // Prioritize loading user data as early as possible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        if (!authProvider.isLoggedIn || authProvider.token == null) {
          Navigator.pushReplacementNamed(context, '/login');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Please log in to access your profile.')),
          );
          return;
        }

        // Initialize WebSocket state from static manager
        _isWebSocketConnected = WebSocketManager.isConnected;
        _isConnectingWebSocket = WebSocketManager.isConnecting;

        // Load user data first - this is the highest priority
        loadData();

        // Then do the other setup steps
        _verifyConnectionStatus();
        _checkEspHealth();
        _getCurrentLocation();
        startBeatPolling();

        // If we have a WebSocket connection, set up the listener
        if (WebSocketManager.isConnected && WebSocketManager.channel != null) {
          _setupWebSocketListener(WebSocketManager.channel!);
        }
      }
    });
  }

  @override
  void dispose() {
    // Only perform disposal if safe to do so
    if (ResourceManager.isSafeToDispose(_instanceId)) {
      print('ProfilePage: Safe disposal of $_instanceId');

      // Cancel animation controller
      _heartAnimationController.dispose();

      // Cancel timer
      if (_beatTimer != null) {
        _beatTimer!.cancel();
        _beatTimer = null;
      }

      // Don't disconnect WebSocket here, it's managed by WebSocketManager
    } else {
      print(
          'ProfilePage: Skipping disposal for $_instanceId as it may be reused');
    }

    // Always unregister from resource manager
    ResourceManager.unregister(_instanceId);

    super.dispose();
  }

  Future<void> _checkEspHealth() async {
    try {
      final isConnected = await ApiService().checkEspHealth();
      setState(() {
        this.isHardwareConnected = isConnected;
      });
    } catch (e) {
      print('Error checking ESP health: $e');
      setState(() {
        this.isHardwareConnected = false;
      });
    }
  }

  Future<void> _updateMapLocation() async {
    if (currentPosition == null) return;

    final lat = currentPosition!.latitude;
    final lng = currentPosition!.longitude;

    final double offset = 0.01;
    final String bbox =
        '${lng - offset}%2C${lat - offset}%2C${lng + offset}%2C${lat + offset}';

    final String mapUrl =
        'https://www.openstreetmap.org/export/embed.html?bbox=$bbox&layer=mapnik&marker=$lat%2C$lng';

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
      final locLat = location['coordinates']['latitude'] as double;
      final locLng = location['coordinates']['longitude'] as double;

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
      final locLat = location['coordinates']['latitude'] as double;
      final locLng = location['coordinates']['longitude'] as double;
      markers.add('$locLat,$locLng');
    }

    final String markersParam = markers.join('&marker=');
    final String bbox = '$minLng%2C$minLat%2C$maxLng%2C$maxLat';

    final String mapUrl =
        'https://www.openstreetmap.org/export/embed.html?bbox=$bbox&layer=mapnik&marker=$markersParam';

    await _webViewController.loadRequest(Uri.parse(mapUrl));
  }

  Future<void> _getCurrentLocation() async {
    if (!mounted) return; // Add early return check

    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return; // Check if still mounted after async call
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
        if (!mounted) return; // Check if still mounted after async call
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are denied.')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return; // Check if still mounted after async call
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
      if (!mounted) return; // Check if still mounted after async call

      safeSetState(() {
        // Use safeSetState instead of setState
        currentPosition = position;
      });

      _updateMapLocation();
    } catch (e) {
      if (!mounted) return; // Check if still mounted after async call
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: $e')),
      );
    }
  }

  Future<void> loadData() async {
    if (!mounted) return; // Add early return check

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

    // Set loading state
    safeSetState(() {
      // Use safeSetState instead of setState
      _hasError = false;
      _errorMessage = '';
    });

    try {
      // Try to fetch user profile
      Map<String, dynamic>? userProfileData;
      try {
        userProfileData = await ApiService().getUserProfile(token);
        if (!mounted) return; // Check if still mounted after async call
        safeSetState(() {
          // Use safeSetState instead of setState
          userData = userProfileData;
        });
      } catch (e) {
        print('Error loading user profile: $e');
        // Don't throw here, continue with other data fetching
      }

      // Handle companion viewing patient data
      if (userProfileData != null &&
          userProfileData['role'] == 'Companion' &&
          userProfileData['patientId'] != null) {
        try {
          // Get the patient's data
          final patient = await ApiService()
              .getCompanion(token, userProfileData['patientId']);
          if (!mounted) return; // Check if still mounted after async call
          safeSetState(() {
            // Use safeSetState instead of setState
            patientData = patient;
            patientId = userProfileData?['patientId'];
          });

          // Show a message that companion is viewing patient data
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Viewing data for ${patient['name']}')),
          );
        } catch (e) {
          print('Error loading patient data: $e');
          // Continue even if this fails
        }
      }

      // Only try to get companion data if user profile was loaded successfully
      if (userProfileData != null &&
          userProfileData['role'] == 'Patient' &&
          userProfileData['companionId'] != null) {
        try {
          final companion = await ApiService()
              .getCompanion(token, userProfileData['companionId']);
          if (!mounted) return; // Check if still mounted after async call
          safeSetState(() {
            // Use safeSetState instead of setState
            companionData = companion;
          });
        } catch (e) {
          print('Error loading companion data: $e');
          // Continue even if this fails
        }
      }

      // Only try to get doctor data if user profile was loaded successfully
      if (userProfileData != null &&
          userProfileData['role'] == 'Patient' &&
          userProfileData['doctorId'] != null) {
        try {
          final doctor = await ApiService()
              .getCompanion(token, userProfileData['doctorId']);
          if (!mounted) return; // Check if still mounted after async call
          safeSetState(() {
            // Use safeSetState instead of setState
            doctorData = doctor;
          });
        } catch (e) {
          print('Error loading doctor data: $e');
          // Continue even if this fails
        }
      }

      // Try to get location data, but don't prevent other data from loading if it fails
      try {
        final latitude = currentPosition?.latitude ?? 30.033333;
        final longitude = currentPosition?.longitude ?? 31.233334;
        final locations =
            await ApiService().getNearbyLocations(token, latitude, longitude);
        if (!mounted) return; // Check if still mounted after async call
        safeSetState(() {
          // Use safeSetState instead of setState
          nearbyLocations = locations;
        });
      } catch (e) {
        print('Failed to fetch nearby locations: $e');
        // Continue even if this fails
      }

      // Try to get unseen message count
      try {
        final count = await ApiService().getUnseenMessageCount(token);
        if (!mounted) return; // Check if still mounted after async call
        safeSetState(() {
          // Use safeSetState instead of setState
          unseenMessageCount = count;
        });
      } catch (e) {
        print('Failed to fetch unseen message count: $e');
        if (mounted) {
          safeSetState(() {
            // Use safeSetState instead of setState
            unseenMessageCount = 0;
          });
        }
      }

      // Try to get reading dates - use patientId for companions
      try {
        List<String> dates;
        if (userData != null) {
          if (userData!['role'] == 'Companion' && patientId != null) {
            // For companions, get patient's reading dates
            dates = await ApiService().getReadingDates(token, patientId);
          } else {
            // For patients, get their own reading dates
            dates = await ApiService().getReadingDates(token);
          }

          if (!mounted) return; // Check if still mounted after async call
          safeSetState(() {
            // Use safeSetState instead of setState
            datesWithData = dates;
          });

          final now = DateTime.now();
          final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
          final endOfWeek = startOfWeek.add(const Duration(days: 6));

          List<Map<String, dynamic>> readings;
          if (userData!['role'] == 'Companion' && patientId != null) {
            // For companions, get patient's readings
            readings = await ApiService()
                .getReadings(token, startOfWeek, endOfWeek, patientId);
          } else {
            // For patients, get their own readings
            readings =
                await ApiService().getReadings(token, startOfWeek, endOfWeek);
          }

          if (!mounted) return; // Check if still mounted after async call
          safeSetState(() {
            // Use safeSetState instead of setState
            weeklyReadings = readings;
            bloodPressureData = _generateWeeklyData(readings);
          });

          final todayStr = DateFormat('yyyy-MM-dd').format(now);
          if (dates.contains(todayStr)) {
            await _loadReadingsForDate(now);
          }
        }
      } catch (e) {
        print('Failed to fetch reading data: $e');
        // Continue even if this fails
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
        if (!mounted) return; // Check if still mounted before updating state
        safeSetState(() {
          // Use safeSetState instead of setState
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

    // Initialize the map with empty lists for all days
    for (int i = 0; i < 7; i++) {
      dailyReadings[i] = [];
    }

    // Add readings to their respective days
    for (var reading in readings) {
      final timestamp = DateTime.parse(reading['timestamp']);
      final dayOffset = timestamp.difference(startOfWeek).inDays;
      if (dayOffset >= 0 && dayOffset < 7) {
        dailyReadings[dayOffset]!.add(reading);
      }
    }

    // Create spots for the chart with proper zero handling
    List<FlSpot> spots = [];
    for (int day = 0; day < 7; day++) {
      final dayReadings = dailyReadings[day] ?? [];
      if (dayReadings.isEmpty) {
        // Use a spot with zero value for empty days
        spots.add(FlSpot(day.toDouble(), 0));
        continue;
      }

      // Calculate average heart rate for the day
      double avgHeartRate = dayReadings
              .map((r) => r['heartRate'] is int
                  ? (r['heartRate'] as int).toDouble()
                  : r['heartRate'] as double)
              .reduce((a, b) => a + b) /
          dayReadings.length;

      spots.add(FlSpot(day.toDouble(), avgHeartRate));
    }

    return spots;
  }

  Future<void> _loadReadingsForDate(DateTime date) async {
    if (!mounted) return;

    safeSetState(() {
      selectedDate = date;
      selectedDateReadings = [];
    });

    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token ?? '';
    if (token.isEmpty) return;

    try {
      List<Map<String, dynamic>> readings;

      // Check if the current user is a companion viewing patient data
      if (userData != null &&
          userData!['role'] == 'Companion' &&
          patientId != null) {
        // For companions, get readings for their patient using patientId
        readings = await ApiService()
            .getReadings(token, startOfDay, endOfDay, patientId);
      } else {
        // For patients, get their own readings
        readings = await ApiService().getReadings(token, startOfDay, endOfDay);
      }

      if (mounted) {
        // Sort readings by timestamp to ensure proper chart display
        readings.sort((a, b) {
          final aTime = DateTime.parse(a['timestamp']);
          final bTime = DateTime.parse(b['timestamp']);
          return aTime.compareTo(bTime);
        });

        safeSetState(() {
          selectedDateReadings = readings;
          if (readings.isNotEmpty) {
            // Ensure values are converted to double
            currentBpm = readings.last['heartRate'] is int
                ? readings.last['heartRate'].toDouble()
                : readings.last['heartRate'];
            currentSpO2 = readings.last['spo2'] is int
                ? readings.last['spo2'].toDouble()
                : readings.last['spo2'];
          }
        });
      }
    } catch (e) {
      print('Error loading readings for date: $e');
      // Show a snackbar if this is a user-initiated action (not from auto-load)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading readings: $e')),
        );
      }
    }
  }

  void startBeatPolling() {
    _beatTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      // Check if widget is still mounted before proceeding
      if (!mounted) {
        timer.cancel();
        return;
      }

      try {
        // Skip polling if ESP is not connected to avoid crashes
        if (!isHardwareConnected) {
          return;
        }

        // If WebSocket is connected, don't use HTTP to poll for beats
        if (_isWebSocketConnected && isMeasurementActive) {
          return;
        }

        final beatData = await ApiService().getBeatData();

        // Check mounted again after the async call
        if (!mounted) return;

        setState(() {
          if (beatData['lastBeatTime'] != null &&
              beatData['lastBeatTime'] != lastBeatTime) {
            lastBeatTime = beatData['lastBeatTime'];
            // Trigger heart animation when beat is detected via HTTP as well
            _heartAnimationController.forward(from: 0);
          }
          isMeasurementActive = beatData['measurementActive'];
          beatsDetected = beatData['beatsDetected'];
        });
      } catch (e) {
        print('Error polling beat data: $e');
        // If there's an error connecting to ESP, mark it as not connected
        // This prevents continuous failed requests
        if (isHardwareConnected && mounted) {
          setState(() {
            isHardwareConnected = false;
          });
        }
      }
    });
  }

  void _setupWebSocketListener(WebSocketChannel channel) {
    // Use the WebSocketManager to set up listener instead of direct stream.listen
    WebSocketManager.setupListener((message) {
      // Check if still mounted before processing messages
      if (!mounted) return;

      print('WebSocket message: $message');
      try {
        final data = jsonDecode(message);

        if (data['event'] == 'connected') {
          safeSetState(() {
            _isWebSocketConnected = true;
            _isConnectingWebSocket = false;
          });
          WebSocketManager.isConnected = true;
          WebSocketManager.isConnecting = false;
          print('WebSocket connected successfully');
        } else if (data['event'] == 'pong') {
          // Response to our ping - connection is alive
          WebSocketManager.handlePong();
          safeSetState(() {
            _isWebSocketConnected = true;
          });
        } else if (data['event'] == 'finger_removed') {
          // Handle finger removed event
          if (isMeasurementActive) {
            safeSetState(() {
              isMeasurementActive = false;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text(data['message'] ?? 'Finger removed from sensor')),
            );
          }
        } else if (data['event'] == 'beat_detected') {
          // Trigger heart animation
          _heartAnimationController.forward(from: 0);

          safeSetState(() {
            lastBeatTime = data['beat_time'];
            beatsDetected = data['beat_count'];
            currentBpm = data['current_bpm'].toDouble();
          });
        } else if (data['event'] == 'sensor_data') {
          safeSetState(() {
            if (data['heart_rate'] != null && data['heart_rate'] > 0) {
              currentBpm = data['heart_rate'].toDouble();
            }
            if (data['spo2'] != null && data['spo2'] > 0) {
              currentSpO2 = data['spo2'].toDouble();
            }
            isMeasurementActive = data['measurement_active'];
            beatsDetected = data['beats_detected'];
            // If finger is not present, show alert
            if (data['finger_present'] != null &&
                data['finger_present'] == false &&
                isMeasurementActive) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Please place your finger on the sensor')),
              );
            }
          });
        } else if (data['event'] == 'measurement_complete') {
          safeSetState(() {
            isMeasurementActive = false;
            if (data['final_heart_rate'] != null) {
              currentBpm = data['final_heart_rate'].toDouble();
            }
          });

          // Save the reading to the backend
          _saveReadingToBackend().then((_) {
            if (mounted) {
              // Clear the results on the ESP to prevent duplicates
              ApiService().clearReadingResults();

              // Show success message
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Measurement complete! Reading saved.')),
              );
            }
          });
        }
      } catch (e) {
        print('Error processing WebSocket message: $e');
      }
    }, () {
      // onDone
      // Check if still mounted before updating state
      if (!mounted) return;

      print('WebSocket connection closed');
      safeSetState(() {
        _isWebSocketConnected = false;
        _isConnectingWebSocket = false;
      });
      WebSocketManager.isConnected = false;
      WebSocketManager.isConnecting = false;
    }, (error) {
      // onError
      // Check if still mounted before updating state
      if (!mounted) return;

      print('WebSocket error: $error');
      safeSetState(() {
        _isWebSocketConnected = false;
        _isConnectingWebSocket = false;
      });
      WebSocketManager.isConnected = false;
      WebSocketManager.isConnecting = false;
    });
  }

  void _startWebSocketMeasurement() {
    if (!WebSocketManager.isConnected || WebSocketManager.channel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('WebSocket not connected. Please try again.')),
      );
      return;
    }

    final command = jsonEncode({'command': 'start_measurement'});

    // Use the static method to send messages
    WebSocketManager.sendMessage(command);

    setState(() {
      isMeasurementActive = true;
      beatsDetected = 0;
    });
  }

  Future<void> _saveReadingToBackend() async {
    if (currentBpm <= 0 || currentSpO2 <= 0) {
      return;
    }

    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Location not available. Reading saved without location.')),
      );
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token ?? '';
    if (token.isEmpty) return;

    try {
      final url = '${ApiService.baseUrl}/readings';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'heartRate': currentBpm,
          'spo2': currentSpO2,
          'latitude': currentPosition?.latitude,
          'longitude': currentPosition?.longitude,
        }),
      );

      if (response.statusCode == 201) {
        print('Reading saved successfully');
        // Reload readings for selected date if exists
        if (selectedDate != null) {
          await _loadReadingsForDate(selectedDate!);
        }
      } else {
        print('Failed to save reading: ${response.body}');
      }
    } catch (e) {
      print('Error saving reading: $e');
    }
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

    // Don't auto-connect to WebSocket
    if (!_isWebSocketConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'WebSocket not connected. Please use the Connect button to establish a connection.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (_isWebSocketConnected) {
      _startWebSocketMeasurement();
    } else {
      // Start HTTP-based measurement (non-blocking now)
      try {
        final apiService = ApiService();
        final response = await apiService.startNonBlockingReading();

        if (response['status'] == 'started') {
          setState(() {
            isMeasurementActive = true;
            beatsDetected = 0;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Measurement started. Please wait...')),
          );

          // Start polling for results
          _pollForResults();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Error starting measurement: ${response['message']}')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting reading: $e')),
        );
      }
    }
  }

  // Poll for measurement results
  Future<void> _pollForResults() async {
    if (!mounted) return;

    const pollInterval = Duration(seconds: 2);
    const maxAttempts = 20; // 40 seconds max
    int attempts = 0;

    Timer.periodic(pollInterval, (timer) async {
      attempts++;

      // Check if still mounted
      if (!mounted || attempts > maxAttempts) {
        timer.cancel();
        return;
      }

      try {
        final apiService = ApiService();
        final resultResponse = await apiService.getReadingResults();

        // Check mounted again after await
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (resultResponse['status'] == 'success') {
          setState(() {
            // Ensure values are converted to double
            currentBpm = resultResponse['heartRate'] is int
                ? resultResponse['heartRate'].toDouble()
                : resultResponse['heartRate'];
            currentSpO2 = resultResponse['spo2'] is int
                ? resultResponse['spo2'].toDouble()
                : resultResponse['spo2'];
            isMeasurementActive = false;
            beatsDetected = resultResponse['beatsDetected'];
          });

          // Save reading to backend
          _saveReadingToBackend();

          // Reload readings for selected date if exists
          if (mounted && selectedDate != null) {
            await _loadReadingsForDate(selectedDate!);
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Measurement complete! Reading saved.')),
            );
          }

          timer.cancel();
        } else if (!resultResponse['measurement_active'] &&
            !resultResponse['server_busy']) {
          // Measurement was canceled or failed
          if (mounted) {
            setState(() {
              isMeasurementActive = false;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Measurement was canceled. Please try again.')),
            );
          }

          timer.cancel();
        }
      } catch (e) {
        print('Error polling for results: $e');
      }
    });
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

  Future<void> _sendLocationOnly(
      String recipientId, String recipientName) async {
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

  // Add the new navigation method
  void _navigateToViewAnalysis() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ViewAnalysisPage(),
      ),
    ).then((_) {
      // When returning from ViewAnalysisPage, reload this page
      if (mounted) {
        reloadPage(context);
      }
    });
  }

  // Update verifyConnectionStatus to use safeSetState
  Future<void> _verifyConnectionStatus() async {
    if (!mounted) return;

    // If we think we're connected, verify it
    if (WebSocketManager.isConnected) {
      print('Verifying WebSocket connection status...');
      final isActive = await WebSocketManager.checkConnectionStatus();

      safeSetState(() {
        _isWebSocketConnected = isActive;
      });

      // Connection is dead but we thought it was alive
      if (!isActive && WebSocketManager.isConnected) {
        print(
            'Connection appears dead but was marked as connected - reconnecting');
        WebSocketManager.isConnected = false;

        // Try to reconnect after a short delay
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (mounted) {
              _connectWebSocket();
            }
          });
        }
      }
    }
    // If we're not connected but device manager says ESP is connected, try to connect
    else if (!WebSocketManager.isConnected &&
        isHardwareConnected &&
        !_isConnectingWebSocket) {
      print('ESP is connected but WebSocket is not - attempting to connect');
      if (mounted) {
        _connectWebSocket();
      }
    }
  }

  // Modify all setState calls to use safeSetState in a few critical methods

  Future<void> _connectWebSocket() async {
    // Check if widget is still mounted
    if (!mounted) return;

    // Don't try to connect again if already connecting
    if (_isConnectingWebSocket) {
      print('Already trying to connect - skipping duplicate attempt');
      return;
    }

    // Ensure we disconnect any old connections first
    WebSocketManager.disconnect();

    safeSetState(() {
      _isConnectingWebSocket = true;
    });

    // Update the static manager state
    WebSocketManager.isConnecting = true;

    try {
      final wsUrl = await ApiService().getWebSocketUrl();
      print('Connecting to WebSocket: $wsUrl');

      // Create new connection
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      WebSocketManager.setChannel(channel, wsUrl);

      // Set up the listener
      _setupWebSocketListener(channel);

      // Immediately send a ping to verify connection
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        final pingResult = await WebSocketManager.checkConnectionStatus();
        if (mounted) {
          setState(() {
            _isWebSocketConnected = pingResult;
            _isConnectingWebSocket = false;
          });
        }

        if (!pingResult) {
          print('Initial ping failed - connection appears unreliable');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Connection unstable - try again')),
          );
        }
      }
    } catch (e) {
      // Check if still mounted before updating state
      if (!mounted) return;

      print('Failed to connect to WebSocket: $e');
      setState(() {
        _isWebSocketConnected = false;
        _isConnectingWebSocket = false;
      });
      WebSocketManager.isConnected = false;
      WebSocketManager.isConnecting = false;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect to sensor: $e')),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Verify connection status when dependencies change (e.g., after navigation)
    _verifyConnectionStatus();

    // Refresh unseen message count when returning to the page
    _refreshUnseenMessageCount();
  }

  @override
  void didUpdateWidget(ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Verify connection status when widget updates
    _verifyConnectionStatus();
  }

  // Add a new method to refresh unseen message count
  Future<void> _refreshUnseenMessageCount() async {
    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token ?? '';
    if (token.isEmpty) return;

    try {
      final count = await ApiService().getUnseenMessageCount(token);
      if (mounted) {
        safeSetState(() {
          unseenMessageCount = count;
        });
      }
    } catch (e) {
      print('Error refreshing unseen message count: $e');
    }
  }

  // Add new method to handle navigation to device manager
  void _navigateToDeviceManager() {
    Navigator.pushNamed(context, '/device_manager').then((_) {
      if (mounted) {
        // When returning from device manager, verify connection status
        _verifyConnectionStatus();
        // Also refresh hardware connection status
        _checkEspHealth();
      }
    });
  }

  // Add a method for safe logout
  void _logout(BuildContext context) {
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
              // Safe disposal of all resources
              ResourceManager.disposeAll();

              // Request explicit disposal of WebSocket connection
              WebSocketManager.requestDispose();

              // Logout using AuthProvider
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text(
          userData != null &&
                  userData!['role'] == 'Companion' &&
                  patientData != null
              ? 'Profile - ${patientData!['name']}'
              : 'Profile',
          style: const TextStyle(color: Colors.white, fontSize: 24),
        ),
        leading: IconButton(
          icon: const Icon(Icons.logout, color: Colors.white, size: 30),
          onPressed: () => _logout(context),
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.message, color: Colors.white, size: 30),
                onPressed: () {
                  Navigator.pushNamed(context, '/user_selection').then((_) {
                    // Refresh unseen message count when returning from messages
                    _refreshUnseenMessageCount();
                  });
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
      body: userData == null
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Loading profile data...',
                    style: TextStyle(fontSize: 18),
                  ),
                ],
              ),
            )
          : _hasError
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
                          safeSetState(() {
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
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () {
                          _navigateToDeviceManager();
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
                            const Spacer(),
                            // Add Reconnect WebSocket Button
                            ElevatedButton.icon(
                              onPressed: _isConnectingWebSocket
                                  ? null
                                  : _connectWebSocket,
                              icon: _isConnectingWebSocket
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.refresh),
                              label: Text(_isWebSocketConnected
                                  ? 'Reconnect'
                                  : 'Connect'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isWebSocketConnected
                                    ? Colors.blue.shade700
                                    : Colors.blue,
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
                          if (!mounted) return;

                          final now = DateTime.now();
                          final firstDate = DateTime(2000);

                          // Handle the case where there are no dates with data
                          if (datesWithData.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('No dates with readings available')),
                            );
                            return;
                          }

                          // Find the most recent date with data to use as initial date
                          DateTime initialDate = now;
                          final dateFormat = DateFormat('yyyy-MM-dd');

                          // Sort dates in descending order and find the first valid one
                          final sortedDates = datesWithData.toList()
                            ..sort((a, b) => b.compareTo(a));

                          if (sortedDates.isNotEmpty) {
                            final mostRecentDate =
                                DateTime.parse(sortedDates.first);
                            if (mostRecentDate.isBefore(now)) {
                              initialDate = mostRecentDate;
                            }
                          }

                          // Make sure initialDate satisfies the predicate
                          final dateStr = dateFormat.format(initialDate);
                          if (!datesWithData.contains(dateStr)) {
                            // If initialDate is not valid, find the first valid date
                            for (var dateStr in sortedDates) {
                              initialDate = DateTime.parse(dateStr);
                              break;
                            }
                          }

                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: initialDate,
                            firstDate: firstDate,
                            lastDate: now,
                            selectableDayPredicate: (DateTime date) {
                              final dateStr = dateFormat.format(date);
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

                          if (pickedDate != null && mounted) {
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
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                // Shadow effect
                                if (lastBeatTime.isNotEmpty &&
                                    isMeasurementActive)
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.red.withOpacity(0.3),
                                          blurRadius: 15,
                                          spreadRadius: 5,
                                        ),
                                      ],
                                    ),
                                  ),
                                // Heart icon with scale animation
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  transform: Matrix4.identity()
                                    ..scale(_heartScale),
                                  child: Icon(
                                    Icons.favorite,
                                    color: _isWebSocketConnected &&
                                            isMeasurementActive
                                        ? Colors.red
                                        : _isWebSocketConnected
                                            ? Colors.orange
                                            : Colors.grey,
                                    size: 40,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        isMeasurementActive
                                            ? 'Measuring... ($beatsDetected beats)'
                                            : 'Measurement Complete',
                                        style: const TextStyle(fontSize: 18),
                                      ),
                                      if (_isWebSocketConnected)
                                        const Padding(
                                          padding: EdgeInsets.only(left: 8.0),
                                          child: Icon(
                                            Icons.wifi,
                                            color: Colors.green,
                                            size: 16,
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (currentBpm > 0)
                                    Text(
                                      'BPM: ${currentBpm.toStringAsFixed(1)}',
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  if (currentSpO2 > 0)
                                    Text(
                                      'SpO2: ${currentSpO2.toStringAsFixed(1)}%',
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  if (_isConnectingWebSocket)
                                    const Text(
                                      'Connecting to sensor...',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontStyle: FontStyle.italic),
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
                        // Daily Heart Rate Chart section with title
                        const Text(
                          'Heart Rate Over Time',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text('Normal Range (60-100 BPM)'),
                            const SizedBox(width: 12),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text('Abnormal Reading'),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Container(
                          height: 250,
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          child: LineChart(
                            LineChartData(
                              gridData: const FlGridData(show: true),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      int index = value.toInt();
                                      if (index >= 0 &&
                                          index < selectedDateReadings.length) {
                                        DateTime time = DateTime.parse(
                                            selectedDateReadings[index]
                                                ['timestamp']);
                                        return Text(
                                          DateFormat('HH:mm').format(time),
                                          style: const TextStyle(fontSize: 12),
                                        );
                                      }
                                      return const Text('');
                                    },
                                    interval: selectedDateReadings.length > 8
                                        ? (selectedDateReadings.length / 4)
                                            .ceil()
                                            .toDouble()
                                        : 1,
                                    reservedSize: 28,
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      return Text(
                                        '${value.toInt()}',
                                        style: const TextStyle(fontSize: 12),
                                      );
                                    },
                                    reservedSize: 40,
                                  ),
                                ),
                                topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                              ),
                              borderData: FlBorderData(show: true),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: _generateDailyChartData(),
                                  isCurved: true,
                                  color: Colors.blue,
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: Colors.blue.withOpacity(0.1),
                                  ),
                                  // Color dots based on if they're normal or abnormal
                                  dotData: FlDotData(
                                    show: true,
                                    getDotPainter:
                                        (spot, percent, barData, index) {
                                      // Check if heart rate is normal
                                      bool isNormal = isNormalHeartRate(spot.y);
                                      return FlDotCirclePainter(
                                        radius: 5,
                                        color:
                                            isNormal ? Colors.blue : Colors.red,
                                        strokeWidth: 1,
                                        strokeColor: Colors.white,
                                      );
                                    },
                                  ),
                                ),
                                // Add a special segment for abnormal values
                                LineChartBarData(
                                  spots: _generateDailyChartData()
                                      .where(
                                          (spot) => !isNormalHeartRate(spot.y))
                                      .toList(),
                                  isCurved: false,
                                  color: Colors.transparent,
                                  dotData: FlDotData(
                                    show: true,
                                    getDotPainter:
                                        (spot, percent, barData, index) {
                                      return FlDotCirclePainter(
                                        radius: 6.5,
                                        color: Colors.red.withOpacity(0.5),
                                        strokeWidth: 1.5,
                                        strokeColor: Colors.red,
                                      );
                                    },
                                  ),
                                  belowBarData: BarAreaData(show: false),
                                ),
                              ],
                              minX: 0,
                              maxX: selectedDateReadings.isEmpty
                                  ? 1
                                  : (selectedDateReadings.length - 1)
                                      .toDouble(),
                              minY: _calculateMinY(_generateDailyChartData()),
                              maxY: _calculateMaxY(_generateDailyChartData()),
                              // Add reference lines for normal heart rate range
                              extraLinesData: ExtraLinesData(
                                horizontalLines: [
                                  HorizontalLine(
                                    y: 60,
                                    color: Colors.orange,
                                    strokeWidth: 1,
                                    dashArray: [5, 5],
                                    label: HorizontalLineLabel(
                                      show: true,
                                      style: const TextStyle(
                                        color: Colors.orange,
                                        fontSize: 10,
                                      ),
                                      labelResolver: (line) => 'Min Normal',
                                      alignment: Alignment.topRight,
                                    ),
                                  ),
                                  HorizontalLine(
                                    y: 100,
                                    color: Colors.orange,
                                    strokeWidth: 1,
                                    dashArray: [5, 5],
                                    label: HorizontalLineLabel(
                                      show: true,
                                      style: const TextStyle(
                                        color: Colors.orange,
                                        fontSize: 10,
                                      ),
                                      labelResolver: (line) => 'Max Normal',
                                      alignment: Alignment.topRight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Readings list title with divider
                        const Divider(),
                        const Padding(
                          padding: EdgeInsets.only(top: 10, bottom: 5),
                          child: Text(
                            'Detailed Readings',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        // Readings list
                        ...selectedDateReadings.map((reading) {
                          final timestamp =
                              DateTime.parse(reading['timestamp']);
                          final heartRate = reading['heartRate'] is int
                              ? reading['heartRate'].toDouble()
                              : reading['heartRate'];
                          final spo2 = reading['spo2'] is int
                              ? reading['spo2'].toDouble()
                              : reading['spo2'];

                          final isNormalHR = isNormalHeartRate(heartRate);
                          final isNormalSpO2 = spo2 >= 95;

                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.symmetric(
                                vertical: 4, horizontal: 0),
                            child: ListTile(
                              leading: Icon(
                                Icons.favorite,
                                color: isNormalHR ? Colors.green : Colors.red,
                                size: 28,
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    'BPM: ${heartRate.toStringAsFixed(1)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isNormalHR
                                          ? Colors.black
                                          : Colors.red,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isNormalHR
                                          ? Colors.green.withOpacity(0.2)
                                          : Colors.red.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      getHeartRateLabel(heartRate),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isNormalHR
                                            ? Colors.green[700]
                                            : Colors.red[700],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Row(
                                children: [
                                  Text(
                                    'SpO2: ${spo2.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      color: isNormalSpO2
                                          ? Colors.black87
                                          : Colors.red,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isNormalSpO2
                                          ? Colors.blue.withOpacity(0.2)
                                          : Colors.red.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      isNormalSpO2 ? 'Normal' : 'Low',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isNormalSpO2
                                            ? Colors.blue[700]
                                            : Colors.red[700],
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    DateFormat('HH:mm').format(timestamp),
                                    style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                        const SizedBox(height: 20),
                      ],
                      // Show Weekly Heart Rate Analysis for patients and for companions viewing patient data
                      if (userData != null &&
                          (userData!['role'] == 'Patient' ||
                              (userData!['role'] == 'Companion' &&
                                  patientData != null))) ...[
                        const Text(
                          'Weekly Heart Rate Analysis',
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        // Only show chart if data is available
                        if (bloodPressureData.any((spot) => spot.y > 0))
                          Container(
                            height: 200,
                            padding: const EdgeInsets.all(16),
                            child: LineChart(
                              LineChartData(
                                gridData: const FlGridData(
                                  show: true,
                                  drawVerticalLine: true,
                                  drawHorizontalLine: true,
                                  horizontalInterval:
                                      20, // Changed from 30 to 20 for better spacing
                                ),
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
                                        // Show multiples of 20 for better distribution
                                        if (value % 20 == 0) {
                                          return Text(
                                            '${value.toInt()}',
                                            style:
                                                const TextStyle(fontSize: 10),
                                          );
                                        }
                                        return const Text('');
                                      },
                                      reservedSize: 30,
                                    ),
                                  ),
                                  topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                ),
                                borderData: FlBorderData(show: true),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: bloodPressureData,
                                    isCurved: true,
                                    color: Colors.red,
                                    dotData: const FlDotData(show: true),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      color: Colors.red.withOpacity(0.2),
                                    ),
                                    barWidth: 3,
                                  ),
                                ],
                                minX: 0,
                                maxX: 6,
                                minY: 0, // Always start at zero
                                maxY: _calculateWeeklyMaxY(
                                    bloodPressureData), // Use a modified function for the weekly chart
                                // Add colored horizontal bands to indicate rate ranges
                                extraLinesData: ExtraLinesData(
                                  horizontalLines: [
                                    HorizontalLine(
                                      y: 60,
                                      color: Colors.orange,
                                      strokeWidth: 1,
                                      dashArray: [5, 5],
                                      label: HorizontalLineLabel(
                                        show: true,
                                        style: const TextStyle(
                                          color: Colors.orange,
                                          fontSize: 10,
                                        ),
                                        labelResolver: (line) => 'Min Normal',
                                        alignment: Alignment.topRight,
                                      ),
                                    ),
                                    HorizontalLine(
                                      y: 100,
                                      color: Colors.orange,
                                      strokeWidth: 1,
                                      dashArray: [5, 5],
                                      label: HorizontalLineLabel(
                                        show: true,
                                        style: const TextStyle(
                                          color: Colors.orange,
                                          fontSize: 10,
                                        ),
                                        labelResolver: (line) => 'Max Normal',
                                        alignment: Alignment.topRight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ).animate().fadeIn(duration: 1000.ms).scale()
                        else
                          Container(
                            padding: const EdgeInsets.all(20),
                            alignment: Alignment.center,
                            child: const Text(
                              'No heart rate data available for this week',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text(
                            '* Chart shows average heart rate by day of the week',
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _navigateToViewAnalysis,
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
                              child: Text(
                                isMeasurementActive ? 'Reading...' : 'Read Now',
                                style: const TextStyle(fontSize: 18),
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
                                                style: const TextStyle(
                                                    fontSize: 14),
                                              ),
                                            if (companionData!['email'] != null)
                                              Text(
                                                'Email: ${companionData!['email']}',
                                                style: const TextStyle(
                                                    fontSize: 14),
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
                        if (userData!['role'] == 'Patient' &&
                            doctorData != null)
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
                                            if (doctorData!['phoneNumber'] !=
                                                null)
                                              Text(
                                                'Phone: ${doctorData!['phoneNumber']}',
                                                style: const TextStyle(
                                                    fontSize: 14),
                                              ),
                                            if (doctorData!['email'] != null)
                                              Text(
                                                'Email: ${doctorData!['email']}',
                                                style: const TextStyle(
                                                    fontSize: 14),
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

  // Calculate appropriate minimum Y value for chart
  double _calculateMinY(List<FlSpot> chartData) {
    if (chartData.isEmpty) return 40;

    double minValue =
        chartData.map((spot) => spot.y).reduce((a, b) => a < b ? a : b);
    // Add padding below the minimum value (about 10% lower), but not below 40
    return max(40, minValue - 10);
  }

  // Calculate appropriate maximum Y value for chart
  double _calculateMaxY(List<FlSpot> chartData) {
    if (chartData.isEmpty) return 140;

    double maxValue =
        chartData.map((spot) => spot.y).reduce((a, b) => a > b ? a : b);
    // Add padding above the maximum value (about 10% higher), but cap at 180
    return min(180, maxValue + 10);
  }

  // Generate chart data from selected date readings
  List<FlSpot> _generateDailyChartData() {
    if (selectedDateReadings.isEmpty) {
      return [];
    }

    // Sort readings by timestamp
    final sortedReadings = List<Map<String, dynamic>>.from(selectedDateReadings)
      ..sort((a, b) {
        final aTime = DateTime.parse(a['timestamp']);
        final bTime = DateTime.parse(b['timestamp']);
        return aTime.compareTo(bTime);
      });

    // Create FlSpot points where x is the index and y is the heart rate value
    return sortedReadings.asMap().entries.map((entry) {
      int index = entry.key;
      double heartRate = entry.value['heartRate'] is int
          ? entry.value['heartRate'].toDouble()
          : entry.value['heartRate'];
      return FlSpot(index.toDouble(), heartRate);
    }).toList();
  }

  // Determine if a heart rate value is within normal range (60-100 BPM)
  bool isNormalHeartRate(double heartRate) {
    return heartRate >= 60 && heartRate <= 100;
  }

  // Get text label for heart rate status
  String getHeartRateLabel(double heartRate) {
    if (heartRate > 100) return 'Above Normal';
    if (heartRate < 60) return 'Below Normal';
    return 'Normal';
  }

  // Calculate appropriate maximum Y value for weekly chart with better scaling
  double _calculateWeeklyMaxY(List<FlSpot> chartData) {
    if (chartData.isEmpty) return 140;

    // Filter out zero values that shouldn't affect the max
    final validPoints = chartData.where((spot) => spot.y > 0).toList();
    if (validPoints.isEmpty) return 140;

    // Get the maximum value
    double maxValue =
        validPoints.map((spot) => spot.y).reduce((a, b) => a > b ? a : b);

    // Round up to the nearest multiple of 20 and add 10 for padding
    double roundedMax = ((maxValue / 20).ceil() * 20) + 10;

    // Ensure we don't go below 120 (to show the normal range) or above 200
    return min(200, max(120, roundedMax));
  }
}
