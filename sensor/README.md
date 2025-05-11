# ESP8266 Heart Rate and SpO2 Sensor Implementation

This implementation connects a MAX30105 heart rate and SpO2 sensor to an ESP8266 microcontroller, creating a WiFi-enabled health monitoring device that integrates with the HCE (Health Companion for Elderly) application.

## Hardware Requirements

- ESP8266 microcontroller (NodeMCU or similar)
- MAX30105 heart rate and SpO2 sensor
- Jumper wires
- Micro USB cable for power and programming

## Wiring Instructions

Connect the MAX30105 sensor to the ESP8266 as follows:

| MAX30105 Pin | ESP8266 Pin |
|--------------|-------------|
| VIN          | 3.3V        |
| GND          | GND         |
| SCL          | D1 (GPIO 5) |
| SDA          | D2 (GPIO 4) |

## Software Requirements

- PlatformIO (recommended) or Arduino IDE
- Required libraries:
  - ESP8266WiFi
  - ESP8266WebServer
  - WebSockets (by Links2004)
  - Wire
  - SparkFun MAX3010x Pulse and Proximity Sensor Library
  - ArduinoJson (v7.x)

## Setup Instructions

### Using PlatformIO (Recommended)
1. Install PlatformIO in your preferred IDE (VS Code recommended)
2. Clone this repository
3. Open the project in PlatformIO
4. Update the WiFi credentials in `config.h`:
   ```cpp
   #define WIFI_SSID "YourWiFiSSID"
   #define WIFI_PASSWORD "YourWiFiPassword"
   ```
5. Connect your ESP8266 via USB
6. Build and upload the project

### Using Arduino IDE
1. Install the Arduino IDE
2. Add ESP8266 board support to Arduino IDE:
   - Go to File > Preferences
   - Add `http://arduino.esp8266.com/stable/package_esp8266com_index.json` to Additional Boards Manager URLs
   - Go to Tools > Board > Boards Manager
   - Search for and install "ESP8266"
3. Install required libraries via Library Manager (Tools > Manage Libraries):
   - Search for and install "ESP8266WiFi"
   - Search for and install "ESP8266WebServer"
   - Search for and install "WebSockets" by Links2004
   - Search for and install "SparkFun MAX3010x Pulse and Proximity Sensor Library"
   - Search for and install "ArduinoJson" (version 7.x)
4. Open the `esp8266_sensor.cpp` file in Arduino IDE
5. Update the WiFi credentials in `config.h`
6. Select the correct board from Tools > Board > ESP8266 Boards > NodeMCU 1.0
7. Select the correct port from Tools > Port
8. Upload the code to your ESP8266

## API Endpoints

The ESP8266 exposes the following HTTP endpoints:

### 1. Health Check
- **URL**: `/health`
- **Method**: GET
- **Response**: JSON with status information
- **Example Response**:
  ```json
  {
    "status": "UP",
    "timestamp": "12345678",
    "message": "ESP Sensor is running",
    "websocket_port": 81
  }
  ```

### 2. Beat Data
- **URL**: `/beat`
- **Method**: GET
- **Response**: JSON with current beat information
- **Example Response**:
  ```json
  {
    "lastBeatTime": "12345678",
    "measurementActive": true,
    "beatsDetected": 42
  }
  ```

### 3. Start Reading
- **URL**: `/readings`
- **Method**: GET
- **Response**: JSON with heart rate and SpO2 measurements
- **Example Response**:
  ```json
  {
    "status": "success",
    "heartRate": 72.5,
    "spo2": 98.0,
    "beatsDetected": 36,
    "timestamp": "12345678"
  }
  ```

## WebSocket Interface

The sensor also provides a WebSocket interface on port 81 for real-time data streaming:

### Connection
- **URL**: `ws://<ESP8266-IP-ADDRESS>:81`

### Events Received
- **Connected**: Sent when a client connects to the WebSocket
  ```json
  {
    "event": "connected",
    "status": "ok",
    "message": "Connected to ESP8266 Heart Rate Monitor"
  }
  ```

- **Sensor Data**: Sent periodically (every 500ms by default)
  ```json
  {
    "event": "sensor_data",
    "timestamp": "12345678",
    "heart_rate": 75,
    "spo2": 98,
    "measurement_active": true,
    "beats_detected": 12,
    "ir_value": 50000,
    "red_value": 40000,
    "finger_present": true
  }
  ```

- **Beat Detected**: Sent when a heartbeat is detected
  ```json
  {
    "event": "beat_detected",
    "beat_time": "12345678",
    "beat_count": 5,
    "current_bpm": 72
  }
  ```

- **Measurement Complete**: Sent when a measurement cycle completes
  ```json
  {
    "event": "measurement_complete",
    "timestamp": "12345678",
    "final_heart_rate": 73.5,
    "spo2": 97,
    "beats_detected": 36
  }
  ```

### Commands
You can send the following commands to the WebSocket:

- **Start Measurement**:
  ```json
  {
    "command": "start_measurement"
  }
  ```

## Integration with HCE App

The ESP8266 server is designed to work with the HCE Flutter application. The app connects to the ESP8266 using the URL configured in the app settings.

For real device testing, update the connection URL to the actual IP address of your ESP8266 on your local network (displayed in the serial monitor when the ESP8266 connects to WiFi).

## Configuration

The sensor behavior can be customized by modifying the parameters in `config.h`:

- WiFi settings (SSID, password)
- Server ports
- Sensor parameters (LED brightness, sample rate, etc.)
- Measurement duration and thresholds

## Troubleshooting

1. **No sensor found**: Check your wiring connections and ensure the sensor is properly powered.
2. **WiFi connection issues**: Verify your WiFi credentials and ensure the ESP8266 is within range of your WiFi network.
3. **No readings**: Make sure your finger is properly placed on the sensor during measurement.
4. **App can't connect**: Verify that the ESP8266 IP address is correctly configured in the app.
5. **Unstable readings**: Ensure your finger remains still during the measurement process.

## Notes

- The current implementation uses a simplified timestamp. For accurate timestamps, consider implementing NTP time synchronization.
- The SpO2 calculation is an approximation. For medical-grade accuracy, additional calibration would be required.
- The measurement process takes 30 seconds to ensure accurate readings.