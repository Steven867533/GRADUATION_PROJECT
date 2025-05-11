import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../providers/api_service.dart';

class DeviceManagerPage extends StatefulWidget {
  const DeviceManagerPage({super.key});

  @override
  DeviceManagerPageState createState() => DeviceManagerPageState();
}

class DeviceManagerPageState extends State<DeviceManagerPage> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _httpPortController = TextEditingController(text: '80');
  final TextEditingController _wsPortController = TextEditingController(text: '81');
  String? _savedIpAddress; // Store the entered IP address
  int _httpPort = 80; // Default HTTP port
  int _wsPort = 81; // Default WebSocket port
  bool _isHardwareConnected = false; // Hardware connection status
  String _lastUpdateVersion = '1.2.3'; // Simulated last update version
  DateTime _lastConnectedTime = DateTime.now().subtract(const Duration(hours: 2)); // Simulated last connected time
  bool _isTestingConnection = false; // Track if testing connection is in progress
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _loadSavedIpAddress();
  }

  // Load the saved IP address from shared preferences
  Future<void> _loadSavedIpAddress() async {
    final espUrl = await AppConfig.getEspUrl();
    final wsUrl = await _apiService.getWebSocketUrl();
    
    // Check if widget is still mounted before updating state
    if (!mounted) return;
    
    setState(() {
      // Extract IP address and port from URL
      final httpUriInfo = _extractUriInfo(espUrl);
      final wsUriInfo = _extractUriInfo(wsUrl);
      
      _savedIpAddress = httpUriInfo['host'];
      _httpPort = httpUriInfo['port'];
      _wsPort = wsUriInfo['port'];
      
      _ipController.text = _savedIpAddress ?? '';
      _httpPortController.text = _httpPort.toString();
      _wsPortController.text = _wsPort.toString();
    });
    
    // Only test connection if still mounted
    if (mounted) {
      await _testConnection(); // Test the connection on init
    }
  }

  // Extract host and port from URL
  Map<String, dynamic> _extractUriInfo(String url) {
    try {
      final uri = Uri.parse(url);
      return {
        'host': uri.host, 
        'port': uri.port > 0 ? uri.port : uri.scheme == 'ws' ? 81 : 80
      };
    } catch (e) {
      return {'host': url, 'port': 80}; // Default if parsing fails
    }
  }

  // Save the IP address and ports
  Future<void> _saveIpAddress() async {
    // First check if component is still mounted
    if (!mounted) return;
    
    final ipAddress = _ipController.text.trim();
    if (ipAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an IP address')),
      );
      return;
    }

    // Validate IP address format
    final isValidIp = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(ipAddress) ||
                     RegExp(r'^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$').hasMatch(ipAddress);

    if (!isValidIp) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid IP address or hostname')),
      );
      return;
    }
    
    // Parse port numbers
    int httpPort;
    int wsPort;
    
    try {
      httpPort = int.parse(_httpPortController.text.trim());
      wsPort = int.parse(_wsPortController.text.trim());
      
      if (httpPort < 1 || httpPort > 65535 || wsPort < 1 || wsPort > 65535) {
        throw const FormatException('Port must be between 1 and 65535');
      }
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid port numbers (1-65535)')),
      );
      return;
    }

    // Format the ESP URLs
    String espUrl = 'http://$ipAddress:$httpPort';
    String wsUrl = 'ws://$ipAddress:$wsPort';
    
    // Save the ESP URL
    await AppConfig.setEspUrl(espUrl);
    
    // Save the WebSocket port (we'll save it in a separate key for simplicity)
    await AppConfig.setWsPort(wsPort);
    
    // Check if still mounted before updating state
    if (!mounted) return;
    
    setState(() {
      _savedIpAddress = ipAddress;
      _httpPort = httpPort;
      _wsPort = wsPort;
    });
    
    // Only test connection if still mounted
    if (mounted) {
      await _testConnection();
    }
  }

  // Test the connection to the ESP
  Future<void> _testConnection() async {
    // First check if component is still mounted
    if (!mounted) return;
    
    setState(() {
      _isTestingConnection = true;
    });
    
    try {
      // Check the ESP health
      final isConnected = await _apiService.checkEspHealth();
      
      // Check if still mounted before updating state
      if (!mounted) return;
      
      setState(() {
        _isTestingConnection = false;
        _isHardwareConnected = isConnected;
        if (_isHardwareConnected) {
          _lastConnectedTime = DateTime.now(); // Update last connected time
        }
      });
      
      if (!mounted) return;
      
      if (_isHardwareConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connected to ESP8266 successfully!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to connect to ESP8266. Please check the IP address and try again.')),
        );
      }
    } catch (e) {
      // Check if still mounted before updating state
      if (!mounted) return;
      
      setState(() {
        _isTestingConnection = false;
        _isHardwareConnected = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error testing connection: $e')),
      );
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _httpPortController.dispose();
    _wsPortController.dispose();
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
                      'ESP8266 Connection Configuration',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: _ipController,
                      decoration: InputDecoration(
                        labelText: 'IP Address / Hostname',
                        labelStyle: const TextStyle(fontSize: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        hintText: 'e.g., 192.168.1.1',
                        hintStyle: const TextStyle(fontSize: 16, color: Colors.grey),
                        filled: true,
                        fillColor: Colors.grey[100],
                        prefixIcon: const Icon(Icons.computer),
                      ),
                      style: const TextStyle(fontSize: 18),
                      keyboardType: TextInputType.text,
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _httpPortController,
                            decoration: InputDecoration(
                              labelText: 'HTTP Port',
                              labelStyle: const TextStyle(fontSize: 16),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              hintText: '80',
                              hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
                              filled: true,
                              fillColor: Colors.grey[100],
                              prefixIcon: const Icon(Icons.http),
                            ),
                            style: const TextStyle(fontSize: 16),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: TextField(
                            controller: _wsPortController,
                            decoration: InputDecoration(
                              labelText: 'WebSocket Port',
                              labelStyle: const TextStyle(fontSize: 16),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              hintText: '81',
                              hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
                              filled: true,
                              fillColor: Colors.grey[100],
                              prefixIcon: const Icon(Icons.wifi),
                            ),
                            style: const TextStyle(fontSize: 16),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Help text to explain ports
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'The ESP8266 uses different ports for HTTP and WebSocket connections. Typically, HTTP runs on port 80 and WebSocket on port 81.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    Container(
                      width: double.infinity,
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
                                'Connection',
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _savedIpAddress ?? 'Not Set',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'HTTP: $_httpPort | WS: $_wsPort',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
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