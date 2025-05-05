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

- Arduino IDE
- Required libraries:
  - ESP8266WiFi
  - ESP8266WebServer
  - Wire
  - MAX30105 (SparkFun MAX3010x library)
  - ArduinoJson

## Setup Instructions

1. Install the Arduino IDE
2. Add ESP8266 board support to Arduino IDE:
   - Go to File > Preferences
   - Add `http://arduino.esp8266.com/stable/package_esp8266com_index.json` to Additional Boards Manager URLs
   - Go to Tools > Board > Boards Manager
   - Search for and install "ESP8266"
3. Install required libraries via Library Manager (Tools > Manage Libraries):
   - Search for and install "ESP8266WiFi"
   - Search for and install "ESP8266WebServer"
   - Search for and install "SparkFun MAX3010x Pulse and Proximity Sensor Library"
   - Search for and install "ArduinoJson"
4. Open the `esp8266_sensor.ino` file in Arduino IDE
5. Update the WiFi credentials in the code:
   ```cpp
   const char* ssid = "YourWiFiSSID";     // Replace with your WiFi SSID
   const char* password = "YourWiFiPassword"; // Replace with your WiFi password
   ```
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
    "message": "ESP Sensor is running"
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

## Integration with HCE App

The ESP8266 server is designed to work with the HCE Flutter application. The app connects to the ESP8266 using the URL configured in `AppConfig.espUrl` in the main.dart file.

By default, the app is configured to connect to `http://10.0.2.2:5001` which is the Android emulator's way of accessing localhost:5001. For real device testing, update this URL to the actual IP address of your ESP8266 on your local network.

## Troubleshooting

1. **No sensor found**: Check your wiring connections and ensure the sensor is properly powered.
2. **WiFi connection issues**: Verify your WiFi credentials and ensure the ESP8266 is within range of your WiFi network.
3. **No readings**: Make sure your finger is properly placed on the sensor during measurement.
4. **App can't connect**: Verify that the ESP8266 IP address is correctly configured in the app.

## Notes

- The current implementation uses a simplified timestamp. For accurate timestamps, consider implementing NTP time synchronization.
- The SpO2 calculation is an approximation. For medical-grade accuracy, additional calibration would be required.
- The measurement process takes 30 seconds to ensure accurate readings.