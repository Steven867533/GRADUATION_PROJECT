import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../providers/auth_provider.dart';
import '../providers/api_service.dart';
import 'package:http/http.dart' as http;
import '../screens/profile_page.dart'; // To access WebSocketManager
import 'dart:math' show min, max;

class ViewAnalysisPage extends StatefulWidget {
  const ViewAnalysisPage({super.key});

  @override
  ViewAnalysisPageState createState() => ViewAnalysisPageState();
}

class ViewAnalysisPageState extends State<ViewAnalysisPage> {
  // Real data: Map of DateTime (day) to List of readings
  final Map<DateTime, List<Map<String, dynamic>>> readingsData = {};
  int currentDayIndex = 0; // Index of the current day being viewed
  bool isLoading = true;
  String? patientId; // For companions to view patient data
  String? selectedPatientName; // Display name of selected patient
  DateTime startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime endDate = DateTime.now();
  
  // WebSocket connection
  WebSocketChannel? _channel;
  bool isConnected = false;
  bool isConnecting = false; // Added state for connection in progress
  bool isMeasurementActive = false;
  int beatsDetected = 0;
  double currentHeartRate = 0;
  double currentSpO2 = 0;
  bool fingerPresent = false;
  
  // Add flag to prevent multiple saves
  bool _hasCurrentReadingBeenSaved = false;
  
  // Real-time chart data
  final List<FlSpot> realtimeHeartRateData = [];
  final List<FlSpot> realtimeSpO2Data = [];
  int dataPointCount = 0;
  Timer? _reconnectTimer;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize connection state from WebSocketManager
    isConnected = WebSocketManager.isConnected;
    isConnecting = WebSocketManager.isConnecting;
    _channel = WebSocketManager.channel;
    
    // Check if user is a companion to load their patient's data
    _checkUserRoleAndLoadData();
    
    // Only connect if not already connected
    if (!isConnected && _channel == null) {
      _connectToWebSocket();
    } else if (isConnected && _channel != null) {
      // Set up listener for existing connection
      _setupWebSocketListener(_channel!);
    }
  }
  
  @override
  void dispose() {
    // Properly clean up resources
    print('Disposing ViewAnalysisPage');

    // Cancel any timers
    _reconnectTimer?.cancel();
    
    // Note: Don't disconnect WebSocket here - let ProfilePage handle reconnection
    
    super.dispose();
  }
  
  // Set up WebSocket listener
  void _setupWebSocketListener(WebSocketChannel channel) {
    // Use the WebSocketManager's setupListener method instead of direct stream.listen
    WebSocketManager.setupListener(
      (message) {
        _handleWebSocketMessage(message);
      },
      () {
        // onDone
        print('WebSocket connection closed');
        if (mounted) {
          setState(() {
            isConnected = false;
            isConnecting = false;
          });
        }
        WebSocketManager.isConnected = false;
      },
      (error) {
        // onError
        print('WebSocket error: $error');
        if (mounted) {
          setState(() {
            isConnected = false;
            isConnecting = false;
          });
        }
        WebSocketManager.isConnected = false;
      }
    );
  }
  
  // Connect to WebSocket server on ESP8266
  Future<void> _connectToWebSocket() async {
    if (!mounted) return;
    
    try {
      setState(() {
        isConnecting = true;
      });
      
      WebSocketManager.isConnecting = true;
      
      final apiService = ApiService();
      final wsUrl = await apiService.getWebSocketUrl();
      
      print('Connecting to WebSocket: $wsUrl');
      
      // If we're already connected to the same URL, reuse the connection
      if (WebSocketManager.lastUrl == wsUrl && WebSocketManager.isConnected) {
        setState(() {
          isConnected = true;
          isConnecting = false;
          _channel = WebSocketManager.channel;
        });
        return;
      }
      
      // Disconnect existing connection
      WebSocketManager.disconnect();
      
      // Create new connection
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      WebSocketManager.setChannel(channel, wsUrl);
      _channel = channel;
      
      // Set up the listener
      _setupWebSocketListener(channel);
      
      if (mounted) {
        setState(() {
          isConnected = true;
          isConnecting = false;
        });
      }
      
      WebSocketManager.isConnected = true;
      WebSocketManager.isConnecting = false;
      
    } catch (e) {
      print('Error connecting to WebSocket: $e');
      if (mounted) {
        setState(() {
          isConnected = false;
          isConnecting = false;
        });
        
        WebSocketManager.isConnected = false;
        WebSocketManager.isConnecting = false;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect: $e')),
        );
      }
    }
  }
  
  // Handle WebSocket messages
  void _handleWebSocketMessage(dynamic message) {
    if (!mounted) return;
    
    try {
      final data = jsonDecode(message);
      
      if (data['event'] == 'connected') {
        print('WebSocket connected: ${data['message']}');
        
        if (!data['server_busy']) {
          // Only start measurement if server isn't busy
          _sendStartMeasurementCommand();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Server is busy with another measurement')),
          );
        }
      } 
      else if (data['event'] == 'error') {
        print('WebSocket error: ${data['message']}');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${data['message']}')),
        );
      }
      else if (data['event'] == 'finger_removed') {
        print('Finger removed: ${data['message']}');
        setState(() {
          isMeasurementActive = false;
          fingerPresent = false;
        });
        
        // Show notification to user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Finger removed from sensor. Measurement canceled.')),
        );
        
        // Reset measurement without saving since it was interrupted
        _hasCurrentReadingBeenSaved = false;
      }
      else if (data['event'] == 'measurement_started') {
        print('Measurement started: ${data['timestamp']}');
        setState(() {
          isMeasurementActive = true;
          beatsDetected = 0;
          _hasCurrentReadingBeenSaved = false;
        });
      }
      else if (data['event'] == 'sensor_data') {
        // Regular sensor data update
        setState(() {
          if (data.containsKey('heart_rate') && data['heart_rate'] != null) {
            currentHeartRate = data['heart_rate'].toDouble();
          }
          
          if (data.containsKey('spo2') && data['spo2'] != null) {
            currentSpO2 = data['spo2'].toDouble();
          }
          
          isMeasurementActive = data['measurement_active'] ?? false;
          beatsDetected = data['beats_detected'] ?? 0;
          fingerPresent = data['finger_present'] ?? false;
          
          // Add data point to the real-time chart
          if (currentHeartRate > 0) {
            dataPointCount++;
            
            // Keep the last 30 points
            if (realtimeHeartRateData.length >= 30) {
              realtimeHeartRateData.removeAt(0);
            }
            
            realtimeHeartRateData.add(FlSpot(dataPointCount.toDouble(), currentHeartRate));
            
            if (currentSpO2 > 0) {
              if (realtimeSpO2Data.length >= 30) {
                realtimeSpO2Data.removeAt(0);
              }
              realtimeSpO2Data.add(FlSpot(dataPointCount.toDouble(), currentSpO2));
            }
          }
        });
      }
      else if (data['event'] == 'beat_detected') {
        print('Beat detected: ${data['beat_time']}');
        setState(() {
          beatsDetected = data['beat_count'] ?? beatsDetected;
          if (data.containsKey('current_bpm') && data['current_bpm'] != null) {
            currentHeartRate = data['current_bpm'].toDouble();
          }
        });
      }
      else if (data['event'] == 'measurement_complete') {
        print('Measurement complete: ${data['final_heart_rate']}');
        setState(() {
          isMeasurementActive = false;
          if (data.containsKey('final_heart_rate') && data['final_heart_rate'] != null) {
            currentHeartRate = data['final_heart_rate'].toDouble();
          }
        });
        
        // Only save if we haven't saved this measurement yet
        if (!_hasCurrentReadingBeenSaved) {
          print('Saving reading for the first time...');
          // Mark as saved before starting the async operation to prevent race conditions
          _hasCurrentReadingBeenSaved = true;
          
          // Save the reading to the backend and clear results
          _saveReadingToBackend().then((_) {
            if (mounted) {
              // Clear the results on the ESP to prevent duplicates
              ApiService().clearReadingResults();
            }
          });
        } else {
          print('Ignoring duplicate measurement_complete event - reading already saved');
          
          // Still clear results on the ESP to prevent future duplicates
          if (mounted) {
            ApiService().clearReadingResults();
          }
        }
      }
    } catch (e) {
      print('Error parsing WebSocket message: $e');
    }
  }
  
  // Send command to start measurement
  void _sendStartMeasurementCommand() {
    if (_channel != null && isConnected) {
      print('Sending start measurement command');
      final command = jsonEncode({
        'command': 'start_measurement',
      });
      
      // Reset the saving flag when starting a new measurement
      _hasCurrentReadingBeenSaved = false;
      
      // Use WebSocketManager's sendMessage method instead
      WebSocketManager.sendMessage(command);
    }
  }
  
  // Disconnect from WebSocket
  void _disconnectWebSocket() {
    WebSocketManager.disconnect();
    _channel = null;
    isConnected = false;
    
    setState(() {
      isConnected = false;
    });
  }
  
  // Save reading to backend
  Future<void> _saveReadingToBackend() async {
    if (!mounted) return;
    
    if (currentHeartRate <= 0 || currentSpO2 <= 0) {
      print('Invalid reading values, not saving');
      return;
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
          'heartRate': currentHeartRate,
          'spo2': currentSpO2,
          'latitude': null, // Location not tracked in analysis page
          'longitude': null,
        }),
      );
      
      // Check if still mounted after async operation
      if (!mounted) return;
      
      if (response.statusCode == 201) {
        print('Reading saved successfully');
        // Mark as saved to prevent duplicate saves
        _hasCurrentReadingBeenSaved = true;
        
        // Reload readings data
        _loadReadingsData();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Measurement saved successfully')),
        );
      } else {
        print('Failed to save reading: ${response.body}');
        // Reset the flag so we can try saving again
        _hasCurrentReadingBeenSaved = false;
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save measurement')),
        );
      }
    } catch (e) {
      if (mounted) {
        print('Error saving reading: $e');
        // Reset the flag so we can try saving again
        _hasCurrentReadingBeenSaved = false;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving reading: $e')),
        );
      }
    }
  }
  
  Future<void> _loadReadingsData() async {
    if (!mounted) return;
    
    setState(() {
      isLoading = true;
      readingsData.clear();
    });
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token ?? '';
    final userRole = authProvider.role;
    
    if (token.isEmpty) return;
    
    try {
      // Fetch readings based on date range
      List<Map<String, dynamic>> readings;
      
      if (userRole == 'Companion' && patientId != null) {
        // If companion is viewing patient data, fetch patient's readings
        readings = await ApiService().getReadings(token, startDate, endDate, patientId);
      } else {
        // Otherwise fetch user's own readings
        readings = await ApiService().getReadings(token, startDate, endDate);
      }
      
      // Check if still mounted after async operation
      if (!mounted) return;
      
      // Group readings by day
      for (var reading in readings) {
        final timestamp = DateTime.parse(reading['timestamp']);
        final day = DateTime(timestamp.year, timestamp.month, timestamp.day);
        
        if (!readingsData.containsKey(day)) {
          readingsData[day] = [];
        }
        
        // Add timestamp to the reading data
        reading['time'] = timestamp;
        readingsData[day]!.add(reading);
      }
      
      // Sort days
      final sortedDays = readingsData.keys.toList()
        ..sort((a, b) => a.compareTo(b));
      
      if (sortedDays.isNotEmpty) {
        // Set current day to the most recent day
        currentDayIndex = sortedDays.length - 1;
      }
      
      setState(() {
        isLoading = false;
      });
    } catch (e) {
      print('Error loading readings: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // Get the current day's data
  DateTime get currentDay => readingsData.keys.isEmpty 
      ? DateTime.now() 
      : readingsData.keys.elementAt(currentDayIndex);

  List<Map<String, dynamic>> get currentReadings => 
      readingsData.isEmpty || !readingsData.containsKey(currentDay) 
      ? [] 
      : readingsData[currentDay]!;

  // Navigate to the previous day
  void previousDay() {
    if (currentDayIndex > 0) {
      setState(() {
        currentDayIndex--;
      });
    }
  }

  // Navigate to the next day
  void nextDay() {
    if (currentDayIndex < readingsData.keys.length - 1) {
      setState(() {
        currentDayIndex++;
      });
    }
  }
  
  // Select date range
  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: startDate, end: endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
      });
      _loadReadingsData();
    }
  }

  // Determine the label for heart rate
  String getHeartRateLabel(int heartRate) {
    if (heartRate > 100) return 'Above Normal';
    if (heartRate < 60) return 'Below Normal';
    return 'Normal';
  }
  
  // Determine the label for SpO2
  String getSpO2Label(int spo2) {
    if (spo2 < 95) return 'Below Normal';
    return 'Normal';
  }
  
  // Load patient data for companion
  Future<void> _loadPatientData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token ?? '';
    final userProfile = authProvider.userProfile;
    
    if (token.isEmpty || userProfile == null) return;
    
    setState(() {
      isLoading = true;
    });
    
    try {
      if (userProfile['role'] == 'Companion' && userProfile['patientId'] != null) {
        // Get patient details
        final patient = await ApiService().getCompanion(token, userProfile['patientId']);
        
        if (!mounted) return;
        
        setState(() {
          patientId = userProfile['patientId'];
          selectedPatientName = patient['name'];
        });
        
        // Load the patient's readings
        await _loadReadingsData();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Viewing data for ${patient['name']}')),
        );
      } else {
        setState(() {
          isLoading = false;
        });
        
        // No patient ID found
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No patient assigned to your account')),
        );
      }
    } catch (e) {
      print('Error loading patient data: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading patient data: $e')),
        );
      }
    }
  }

  // Add a method to properly clean up and return to ProfilePage
  void _returnToProfilePage() {
    // Just pop back - the ProfilePage will handle reloading itself
    Navigator.pop(context);
  }

  // New method to check user role and load appropriate data
  Future<void> _checkUserRoleAndLoadData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userRole = authProvider.role;
    
    if (userRole == 'Companion') {
      // If user is a companion, first load their patient's data
      await _loadPatientData();
    } else {
      // For patients or other roles, load their own data directly
      _loadReadingsData();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Prepare chart data from current readings with proper error handling
    List<FlSpot> chartData = [];
    if (currentReadings.isNotEmpty) {
      chartData = currentReadings.asMap().entries.map((entry) {
        int index = entry.key;
        double heartRate = entry.value['heartRate'].toDouble();
        return FlSpot(index.toDouble(), heartRate);
      }).toList();
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text(
          selectedPatientName != null
              ? 'Analysis - $selectedPatientName'
              : 'View Analysis',
          style: const TextStyle(color: Colors.white, fontSize: 24),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
          onPressed: _returnToProfilePage,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range, color: Colors.white),
            onPressed: () => _selectDateRange(context),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: Icon(
                  isConnected ? Icons.wifi : (isConnecting ? Icons.wifi_find : Icons.wifi_off),
                  color: isConnected ? Colors.green : (isConnecting ? Colors.orange : Colors.white),
                ),
                onPressed: isConnecting ? null : (isConnected ? _disconnectWebSocket : _connectToWebSocket),
              ),
              if (isConnecting)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Real-time sensor status
            if (isConnected) ...[
              Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Real-time Sensor Data',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                              vertical: 4.0,
                            ),
                            decoration: BoxDecoration(
                              color: isMeasurementActive ? Colors.green : Colors.orange,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isMeasurementActive ? 'Measuring' : 'Ready',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.favorite, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Heart Rate: ${currentHeartRate.toStringAsFixed(1)} BPM',
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.bloodtype, color: Colors.blue),
                                  const SizedBox(width: 8),
                                  Text(
                                    'SpO2: ${currentSpO2.toStringAsFixed(1)}%',
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Beats: $beatsDetected',
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Finger: ${fingerPresent ? 'Detected' : 'Not Detected'}',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: fingerPresent ? Colors.green : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _sendStartMeasurementCommand,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 45),
                        ),
                        child: const Text(
                          'Start Measurement',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (realtimeHeartRateData.isNotEmpty) ...[
                        const Text(
                          'Real-time Heart Rate',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 200,
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          child: realtimeHeartRateData.length < 2
                            ? const Center(child: Text('Collecting data...'))
                            : LineChart(
                              LineChartData(
                                gridData: const FlGridData(show: false),
                                titlesData: FlTitlesData(
                                  bottomTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (value, meta) {
                                        return Text(
                                          '${value.toInt()}',
                                          style: const TextStyle(fontSize: 10),
                                        );
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
                                borderData: FlBorderData(show: false),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: realtimeHeartRateData,
                                    isCurved: true,
                                    color: Colors.red,
                                    dotData: const FlDotData(show: false),
                                    belowBarData: BarAreaData(show: false),
                                  ),
                                  if (realtimeSpO2Data.length >= 2)
                                    LineChartBarData(
                                      spots: realtimeSpO2Data,
                                      isCurved: true,
                                      color: Colors.blue,
                                      dotData: const FlDotData(show: false),
                                      belowBarData: BarAreaData(show: false),
                                    ),
                                ],
                                minX: realtimeHeartRateData.isEmpty ? 0 : realtimeHeartRateData.first.x,
                                maxX: realtimeHeartRateData.isEmpty ? 1 : realtimeHeartRateData.last.x,
                                minY: 40, // Lower minimum to show more context
                                maxY: 140, // Higher maximum for potential high rates
                              ),
                            ),
                        ),
                        // Re-add the legend for heart rate and SpO2
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 6,
                                backgroundColor: Colors.red,
                              ),
                              SizedBox(width: 8),
                              Text('Heart Rate'),
                              SizedBox(width: 16),
                              CircleAvatar(
                                radius: 6,
                                backgroundColor: Colors.blue,
                              ),
                              SizedBox(width: 8),
                              Text('SpO2'),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            
            // Day Navigation
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_left,
                    size: 40,
                    color: Colors.blue,
                  ),
                  onPressed: currentDayIndex > 0 ? previousDay : null,
                  disabledColor: Colors.grey,
                ),
                Expanded(
                  child: Text(
                    DateFormat('EEEE, MMM d, yyyy').format(currentDay),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.arrow_right,
                    size: 40,
                    color: currentDayIndex < readingsData.keys.length - 1 ? Colors.blue : Colors.grey,
                  ),
                  onPressed: currentDayIndex < readingsData.keys.length - 1 ? nextDay : null,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Time-Based Chart
            const Text(
              'Heart Rate Over Time',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Container(
              height: 300,
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: chartData.length < 2 
                ? const Center(
                    child: Text(
                      'Not enough data for chart display',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: true),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              int index = value.toInt();
                              if (index >= 0 && index < currentReadings.length) {
                                DateTime time = currentReadings[index]['time'];
                                return Text(
                                  DateFormat('HH:mm').format(time),
                                  style: const TextStyle(fontSize: 12),
                                );
                              }
                              return const Text('');
                            },
                            interval: chartData.length > 8 ? (chartData.length / 4).ceil().toDouble() : 1,
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
                          spots: chartData,
                          isCurved: true,
                          color: Colors.blue,
                          dotData: const FlDotData(show: true),
                          belowBarData: BarAreaData(
                            show: true,
                            color: Colors.blue.withOpacity(0.1),
                          ),
                        ),
                      ],
                      minX: 0,
                      maxX: chartData.isEmpty ? 1 : (chartData.length - 1).toDouble(),
                      minY: _calculateMinY(chartData),
                      maxY: _calculateMaxY(chartData),
                    ),
                  ),
            ),
            const SizedBox(height: 20),

            // Table of Readings
            const Text(
              'Daily Readings Summary',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (currentReadings.isEmpty) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text(
                    'No readings available for this day',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
              ),
            ] else ...[
              Table(
                border: TableBorder.all(color: Colors.grey[300]!),
                children: [
                  const TableRow(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(
                          'Time',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(
                          'Heart Rate',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(
                          'SpO2',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(
                          'Status',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  ...currentReadings.asMap().entries.map((entry) {
                          DateTime time = entry.value['time'];
                          num heartRate = entry.value['heartRate'];
                          num spo2 = entry.value['spo2'];
                          String heartRateStatus = getHeartRateLabel(heartRate.toInt());
                          String spo2Status = getSpO2Label(spo2.toInt());
                          Color heartRateColor = heartRateStatus == 'Normal' ? Colors.green : Colors.red;
                          Color spo2Color = spo2Status == 'Normal' ? Colors.green : Colors.red;
                          
                          // Combined status
                          String status = heartRateStatus == 'Normal' && spo2Status == 'Normal' 
                              ? 'Normal' 
                              : 'Abnormal';
                          Color statusColor = status == 'Normal' ? Colors.green : Colors.red;

                          return TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  DateFormat('HH:mm').format(time),
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  heartRate.toString(),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: heartRateColor,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  spo2.toString(),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: spo2Color,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          );
                  }).toList(),
                ],
              ),
            ]
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _sendStartMeasurementCommand,
        backgroundColor: Colors.blue,
        child: const Icon(Icons.monitor_heart, color: Colors.white),
      ),
    );
  }
  
  // Calculate appropriate minimum Y value for chart
  double _calculateMinY(List<FlSpot> chartData) {
    if (chartData.isEmpty) return 40;
    
    double minValue = chartData.map((spot) => spot.y).reduce((a, b) => a < b ? a : b);
    // Add padding below the minimum value (about 10% lower)
    return max(40, minValue - 10);
  }
  
  // Calculate appropriate maximum Y value for chart
  double _calculateMaxY(List<FlSpot> chartData) {
    if (chartData.isEmpty) return 140;
    
    double maxValue = chartData.map((spot) => spot.y).reduce((a, b) => a > b ? a : b);
    // Add padding above the maximum value (about 10% higher)
    return min(180, maxValue + 10);
  }
}