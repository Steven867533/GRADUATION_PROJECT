import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/api_service.dart';

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
  
  @override
  void initState() {
    super.initState();
    _loadReadingsData();
  }
  
  Future<void> _loadReadingsData() async {
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
      setState(() {
        isLoading = false;
      });
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
    
    try {
      if (userProfile['role'] == 'Companion' && userProfile['patientId'] != null) {
        final patient = await ApiService().getCompanion(token, userProfile['patientId']);
        setState(() {
          patientId = userProfile['patientId'];
          selectedPatientName = patient['name'];
        });
        _loadReadingsData();
      }
    } catch (e) {
      print('Error loading patient data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Prepare chart data
    List<FlSpot> chartData = currentReadings.asMap().entries.map((entry) {
      int index = entry.key;
      double systolic = entry.value['systolic'];
      return FlSpot(index.toDouble(), systolic);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text(
          'View Analysis',
          style: TextStyle(color: Colors.white, fontSize: 24),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
          onPressed: () {
            Navigator.pushReplacementNamed(context, '/profile');
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day Navigation
            Row(
              mainAxisSize: MainAxisSize.min, // Prevent Row from taking full width
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
                Expanded( // Wrap Text in Expanded to prevent overflow
                  child: Text(
                    DateFormat('EEEE, MMM d, yyyy').format(currentDay),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis, // Truncate with "..." if too long
                    textAlign: TextAlign.center, // Center the text
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
              'Blood Pressure Over Time',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Container(
              height: 300,
              padding: const EdgeInsets.all(16),
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
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
                              style: const TextStyle(fontSize: 14),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()} mmHg',
                            style: const TextStyle(fontSize: 14),
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
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: chartData,
                      isCurved: true,
                      color: Colors.blue, // Compatible with older fl_chart versions
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                  minX: 0,
                  maxX: (currentReadings.length - 1).toDouble(),
                  minY: 80,
                  maxY: 150,
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
                        'Systolic (mmHg)',
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
                        int heartRate = entry.value['heartRate'];
                        int spo2 = entry.value['spo2'];
                        String heartRateStatus = getHeartRateLabel(heartRate);
                        String spo2Status = getSpO2Label(spo2);
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
          ],
        ),
      ),
    );
  }
}