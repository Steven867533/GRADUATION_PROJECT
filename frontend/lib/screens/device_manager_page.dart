import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

class DeviceManagerPage extends StatefulWidget {
  const DeviceManagerPage({super.key});

  @override
  DeviceManagerPageState createState() => DeviceManagerPageState();
}

class DeviceManagerPageState extends State<DeviceManagerPage> {
  final TextEditingController _ipController = TextEditingController();
  String? _savedIpAddress; // Store the entered IP address
  bool _isHardwareConnected = false; // Hardware connection status
  String _lastUpdateVersion = '1.2.3'; // Simulated last update version
  DateTime _lastConnectedTime = DateTime.now().subtract(const Duration(hours: 2)); // Simulated last connected time
  bool _isTestingConnection = false; // Track if testing connection is in progress

  // Save the IP address and set connection status to "Connected" for any IP
  void _saveIpAddress() {
    setState(() {
      _savedIpAddress = _ipController.text;
      // Set to "Connected" for any IP address (as requested)
      _isHardwareConnected = _ipController.text.isNotEmpty;
      if (_isHardwareConnected) {
        _lastConnectedTime = DateTime.now(); // Update last connected time
      }
    });
  }

  // Simulate testing the connection (always "Connected" for now)
  Future<void> _testConnection() async {
    setState(() {
      _isTestingConnection = true;
    });
    // Simulate a network request delay
    await Future.delayed(const Duration(seconds: 2));
    setState(() {
      _isTestingConnection = false;
      // Set to "Connected" for any IP address (as requested)
      _isHardwareConnected = _savedIpAddress != null && _savedIpAddress!.isNotEmpty;
      if (_isHardwareConnected) {
        _lastConnectedTime = DateTime.now(); // Update last connected time
      }
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue, Colors.blueAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text(
          'Device Manager',
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
            // Connection Status with Integrated Circuit Icon
            Row(
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
                        color: _isHardwareConnected ? Colors.green : Colors.red,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Text(
                  _isHardwareConnected ? 'Connected' : 'Not Connected',
                  style: TextStyle(
                    fontSize: 22,
                    color: _isHardwareConnected ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ).animate().fadeIn(duration: 800.ms).slideX(),
            const SizedBox(height: 20),

            // IP Address Input Section
            Card(
              elevation: 5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter Hardware Module IP Address',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _ipController,
                      decoration: InputDecoration(
                        labelText: 'IP Address',
                        labelStyle: const TextStyle(fontSize: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        hintText: 'e.g., 192.168.1.1',
                        hintStyle: const TextStyle(fontSize: 16, color: Colors.grey),
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                      style: const TextStyle(fontSize: 18),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.blue, Colors.blueAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ElevatedButton(
                        onPressed: _saveIpAddress,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Save & Connect',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(duration: 800.ms).slideY(),
            const SizedBox(height: 20),

            // Hardware Status Table
            Card(
              elevation: 5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hardware Status',
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
                                'IP Address',
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
                            Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                'Action',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                _savedIpAddress ?? 'Not Set',
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                _isHardwareConnected ? 'Connected' : 'Not Connected',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _isHardwareConnected ? Colors.green : Colors.red,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Colors.blue, Colors.blueAccent],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ElevatedButton(
                                  onPressed: _isTestingConnection || _savedIpAddress == null ? null : _testConnection,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    foregroundColor: Colors.white,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: _isTestingConnection
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text(
                                          'Test Connection',
                                          style: TextStyle(fontSize: 16),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(duration: 800.ms).slideY(),
            const SizedBox(height: 20),

            // Hardware Analysis
            Card(
              elevation: 5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hardware Analysis',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.update,
                          color: Colors.blue,
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Last Update Version: $_lastUpdateVersion',
                          style: const TextStyle(fontSize: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          color: Colors.blue,
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          // 'Last Connected: ${DateFormat('MMM d, yyyy, HH:mm').format(_lastConnectedTime)}',
                          'Last Connected: ${DateFormat('MMM d, HH:mm').format(_lastConnectedTime)}',
                          style: const TextStyle(fontSize: 18),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(duration: 800.ms).slideY(),
          ],
        ),
      ),
    );
  }
}