#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <WebSocketsServer.h>  // Add WebSockets library
#include <Wire.h>
#include "MAX30105.h"
#include <ArduinoJson.h>
#include "config.h"  // Include configuration file

// WiFi credentials from config.h
const char* ssid = WIFI_SSID;
const char* password = WIFI_PASSWORD;

// Create web server on port from config.h
ESP8266WebServer server(SERVER_PORT);

// Create WebSocket server on port 81
WebSocketsServer webSocket = WebSocketsServer(81);

// Initialize sensor
MAX30105 particleSensor;

// Timing variables
unsigned long measurementStartTime = 0;
bool measurementActive = false;
bool measurementComplete = false;

// Beat detection variables
unsigned long beatTimes[MAX_BEATS];
int beatCount = 0;
float calculatedBPM = 0;
String lastBeatSystemTime = "";

// Signal processing
long irBuffer[BUFFER_SIZE];
int bufferIndex = 0;
long irDC = 0;    // DC component (baseline)
long irACPrev = 0; // Previous AC value
bool risingSlope = false;
unsigned long lastBeatTime = 0;

// Display variables
int displayedBPM = 0;
int displayedSpO2 = 0;

// WebSocket variables
unsigned long lastBroadcastTime = 0;
#define BROADCAST_INTERVAL 500 // Send data every 500ms

// Status flag to indicate server availability
bool serverBusy = false;

void processRealtimeMeasurement();
void broadcastSensorData();

// New function to clear measurement results
void clearMeasurementResults() {
  // Clear the measurement complete flag but don't reset the whole measurement
  measurementComplete = false;
  Serial.println("Measurement results cleared");
  
  // Return success response
  DynamicJsonDocument doc(256);
  doc["status"] = "success";
  doc["message"] = "Measurement results cleared";
  
  String response;
  serializeJson(doc, response);
  
  server.send(200, "application/json", response);
}

void resetMeasurement() {
  measurementActive = false;
  measurementComplete = false;
  beatCount = 0;
  lastBeatSystemTime = "";
}

void startMeasurement() {
  Serial.println("\n--- STARTING NEW MEASUREMENT ---");
  Serial.println("Hold your finger still for 60 seconds");
  
  // Reset variables
  beatCount = 0;
  calculatedBPM = 0;
  irACPrev = 0;
  risingSlope = false;
  
  // Set timing
  measurementStartTime = millis();
  measurementActive = true;
  measurementComplete = false;
}

void finishMeasurement() {
  measurementActive = false;
  measurementComplete = true;
  
  // Calculate accurate BPM based on collected data
  if (beatCount >= 3) {
    // Calculate time elapsed between first and last beat
    unsigned long totalMeasurementTime = beatTimes[beatCount - 1] - beatTimes[0];
    
    // First, calculate all beat-to-beat intervals
    unsigned long beatIntervals[MAX_BEATS-1];
    int intervalCount = 0;
    
    for (int i = 1; i < beatCount; i++) {
      beatIntervals[intervalCount++] = beatTimes[i] - beatTimes[i-1];
    }
    
    // Calculate median heart rate to filter outliers
    // Simple selection sort for this small array
    for (int i = 0; i < intervalCount - 1; i++) {
      for (int j = i + 1; j < intervalCount; j++) {
        if (beatIntervals[i] > beatIntervals[j]) {
          unsigned long temp = beatIntervals[i];
          beatIntervals[i] = beatIntervals[j];
          beatIntervals[j] = temp;
        }
      }
    }
    
    // Get median interval
    unsigned long medianInterval;
    if (intervalCount % 2 == 0) {
      medianInterval = (beatIntervals[intervalCount/2] + beatIntervals[intervalCount/2 - 1]) / 2;
    } else {
      medianInterval = beatIntervals[intervalCount/2];
    }
    
    // Convert to BPM
    float medianBPM = 60000.0 / medianInterval;
    
    // Also calculate average-based BPM
    float minutesElapsed = totalMeasurementTime / 60000.0;
    float averageBPM = (beatCount - 1) / minutesElapsed;
    
    // Use the median BPM if it's reasonable, otherwise fall back to average
    if (medianBPM >= MIN_VALID_BPM && medianBPM <= MAX_VALID_BPM) {
      calculatedBPM = medianBPM;
    } else {
      calculatedBPM = averageBPM;
    }
    
    // Apply final sanity check
    if (calculatedBPM < MIN_VALID_BPM || calculatedBPM > MAX_VALID_BPM) {
      calculatedBPM = 0;
    }
    
    Serial.print("Measurement complete. Median BPM: ");
    Serial.print(medianBPM);
    Serial.print(", Average BPM: ");
    Serial.print(averageBPM);
    Serial.print(", Final BPM: ");
    Serial.println(calculatedBPM);
  } else {
    calculatedBPM = 0; // Not enough beats detected
    Serial.println("Measurement complete, but not enough beats detected for accurate calculation.");
  }
  
  // Broadcast final results via WebSocket
  broadcastSensorData();
}

// Get current timestamp in ISO8601 format
String getISOTimestamp() {
  // This is a simplified version since ESP8266 doesn't have a real-time clock
  // In a real application, you would use NTP to get the actual time
  return String(millis());
}

// Improve WebSocket event handler to prioritize ping responses
void webSocketEvent(uint8_t num, WStype_t type, uint8_t * payload, size_t length) {
  switch(type) {
    case WStype_DISCONNECTED:
      Serial.printf("[%u] Disconnected!\n", num);
      break;
    case WStype_CONNECTED:
      {
        IPAddress ip = webSocket.remoteIP(num);
        Serial.printf("[%u] Connected from %d.%d.%d.%d url: %s\n", num, ip[0], ip[1], ip[2], ip[3], payload);
        
        // Send welcome message
        DynamicJsonDocument doc(256);
        doc["event"] = "connected";
        doc["status"] = "ok";
        doc["message"] = "Connected to ESP8266 Heart Rate Monitor";
        doc["server_busy"] = serverBusy;
        doc["measurement_active"] = measurementActive;
        doc["measurement_complete"] = measurementComplete;
        
        String response;
        serializeJson(doc, response);
        webSocket.sendTXT(num, response);
      }
      break;
    case WStype_TEXT:
      {
        Serial.printf("[%u] Received text: %s\n", num, payload);
        
        // Parse JSON command
        DynamicJsonDocument doc(256);
        DeserializationError error = deserializeJson(doc, payload);
        
        if (!error) {
          String command = doc["command"];
          
          // Give highest priority to ping - respond immediately
          if (command == "ping") {
            // Respond to ping with a pong to confirm connection is alive
            DynamicJsonDocument pongDoc(256);
            pongDoc["event"] = "pong";
            pongDoc["timestamp"] = getISOTimestamp();
            pongDoc["server_busy"] = serverBusy;
            pongDoc["measurement_active"] = measurementActive;
            
            String pongResponse;
            serializeJson(pongDoc, pongResponse);
            webSocket.sendTXT(num, pongResponse);
            
            // Exit after responding to ping to prioritize response time
            return;
          }
          else if (command == "start_measurement") {
            // Only start if not already busy
            if (!serverBusy && !measurementActive) {
              // Reset and start a new measurement
              resetMeasurement();
              startMeasurement();
              
              // Send acknowledgment
              DynamicJsonDocument responseDoc(256);
              responseDoc["event"] = "measurement_started";
              responseDoc["timestamp"] = getISOTimestamp();
              
              String response;
              serializeJson(responseDoc, response);
              webSocket.sendTXT(num, response);
            } else {
              // Send busy message
              DynamicJsonDocument busyDoc(256);
              busyDoc["event"] = "error";
              busyDoc["message"] = "Server is busy with another measurement";
              busyDoc["timestamp"] = getISOTimestamp();
              
              String busyResponse;
              serializeJson(busyDoc, busyResponse);
              webSocket.sendTXT(num, busyResponse);
            }
          }
          else if (command == "check_status") {
            // Send current status
            DynamicJsonDocument statusDoc(256);
            statusDoc["event"] = "status";
            statusDoc["timestamp"] = getISOTimestamp();
            statusDoc["server_busy"] = serverBusy;
            statusDoc["measurement_active"] = measurementActive;
            statusDoc["measurement_complete"] = measurementComplete;
            statusDoc["beats_detected"] = beatCount;
            
            String statusResponse;
            serializeJson(statusDoc, statusResponse);
            webSocket.sendTXT(num, statusResponse);
          }
        }
      }
      break;
  }
}

// Broadcast sensor data to all connected clients
void broadcastSensorData() {
  DynamicJsonDocument doc(512);
  doc["event"] = "sensor_data";
  doc["timestamp"] = getISOTimestamp();
  doc["heart_rate"] = displayedBPM;
  doc["spo2"] = displayedSpO2;
  doc["measurement_active"] = measurementActive;
  doc["beats_detected"] = beatCount;
  doc["server_busy"] = serverBusy;
  
  // Add more data for final result
  if (measurementComplete) {
    doc["event"] = "measurement_complete";
    doc["final_heart_rate"] = round(calculatedBPM * 10) / 10.0;
  }
  
  // Add raw sensor data if needed
  long irValue = particleSensor.getIR();
  long redValue = particleSensor.getRed();
  doc["ir_value"] = irValue;
  doc["red_value"] = redValue;
  
  // Calculate finger presence
  bool fingerPresent = irValue > FINGER_PRESENCE_THRESHOLD;
  doc["finger_present"] = fingerPresent;
  
  String response;
  serializeJson(doc, response);
  webSocket.broadcastTXT(response);
}

// Handle health check endpoint with priority
void handleHealth() {
  // This function needs to respond quickly
  DynamicJsonDocument doc(256);
  doc["status"] = "UP";
  doc["timestamp"] = getISOTimestamp();
  doc["message"] = "ESP Sensor is running";
  doc["websocket_port"] = 81;  // Add WebSocket info
  doc["server_busy"] = serverBusy;
  doc["measurement_active"] = measurementActive;
  
  String response;
  serializeJson(doc, response);
  
  server.send(200, "application/json", response);
}

// Handle beat data endpoint
void handleBeat() {
  DynamicJsonDocument doc(256);
  doc["lastBeatTime"] = lastBeatSystemTime;
  doc["measurementActive"] = measurementActive;
  doc["beatsDetected"] = beatCount;
  doc["server_busy"] = serverBusy;
  
  String response;
  serializeJson(doc, response);
  
  server.send(200, "application/json", response);
}

// Handle non-blocking readings
void handleReadings() {
  // Check if a measurement is already in progress
  if (measurementActive || serverBusy) {
    DynamicJsonDocument doc(256);
    doc["status"] = "error";
    doc["message"] = "Measurement in progress. Please wait.";
    
    String response;
    serializeJson(doc, response);
    
    server.send(400, "application/json", response);
    return;
  }
  
  // Reset and start a new measurement
  resetMeasurement();
  startMeasurement();
  serverBusy = true; // Mark server as busy
  
  // Return immediately with acknowledgment that measurement has started
  DynamicJsonDocument doc(256);
  doc["status"] = "started";
  doc["message"] = "60-second measurement started. Check /beat for progress.";
  doc["timestamp"] = getISOTimestamp();
  
  String response;
  serializeJson(doc, response);
  
  server.send(200, "application/json", response);
}

// New endpoint for results
void handleReadingResults() {
  DynamicJsonDocument doc(256);
  
  if (measurementComplete) {
    doc["status"] = "success";
    doc["heartRate"] = round(calculatedBPM * 10) / 10.0;
    doc["spo2"] = round(displayedSpO2 * 10) / 10.0;
    doc["beatsDetected"] = beatCount;
    doc["timestamp"] = getISOTimestamp();
    doc["server_busy"] = serverBusy;
    
    // Don't reset the complete flag here anymore
    // We'll let the client explicitly clear it with the new endpoint
  } else {
    doc["status"] = "not_ready";
    doc["message"] = "No completed measurement available";
    doc["measurement_active"] = measurementActive;
    doc["server_busy"] = serverBusy;
  }
  
  String response;
  serializeJson(doc, response);
  
  server.send(200, "application/json", response);
}

// Non-blocking measurement processing - to be called in loop()
void processRealtimeMeasurement() {
  if (!measurementActive) return;
  
  // Read from sensor
  long irValue = particleSensor.getIR();
  long redValue = particleSensor.getRed();
  static unsigned long fingerMissingStartTime = 0;
  
  // Check if finger is placed on sensor
  if (irValue < FINGER_PRESENCE_THRESHOLD) {
    // Finger is missing - start or update the missing finger timer
    if (fingerMissingStartTime == 0) {
      fingerMissingStartTime = millis();
      Serial.println("Finger removed - starting timeout");
    } else if (millis() - fingerMissingStartTime > 2000) { // Reduced from 3s to 2s timeout
      // Cancel the measurement after timeout
      Serial.println("No finger detected for 2 seconds. Measurement canceled.");
      
      // Notify WebSocket clients about finger removal
      DynamicJsonDocument fingerDoc(256);
      fingerDoc["event"] = "finger_removed";
      fingerDoc["message"] = "Finger removed from sensor. Measurement canceled.";
      fingerDoc["timestamp"] = getISOTimestamp();
      
      String fingerResponse;
      serializeJson(fingerDoc, fingerResponse);
      webSocket.broadcastTXT(fingerResponse);
      
      // Reset measurement and clear the busy flag
      resetMeasurement();
      serverBusy = false;
      fingerMissingStartTime = 0;
      return;
    }
  } else {
    // Reset missing finger timer if finger is present
    if (fingerMissingStartTime != 0) {
      Serial.println("Finger detected again");
      fingerMissingStartTime = 0;
    }
  }
  
  // Skip processing if finger is not present
  if (irValue < FINGER_PRESENCE_THRESHOLD) {
    // Still broadcast sensor data to update UI but don't process beats
    broadcastSensorData();
    return;
  }
  
  // Update buffer
  irBuffer[bufferIndex] = irValue;
  bufferIndex = (bufferIndex + 1) % BUFFER_SIZE;
  
  // Calculate DC component (baseline) - moving average
  irDC = 0;
  for (int i = 0; i < BUFFER_SIZE; i++) {
    irDC += irBuffer[i];
  }
  irDC /= BUFFER_SIZE;
  
  // Extract AC component (pulsatile)
  long irAC = irValue - irDC;
  
  // Beat detection using slope detection
  unsigned long currentTime = millis();
  boolean validBeatTiming = (currentTime - lastBeatTime) > MIN_BEAT_INTERVAL;
  
  // Rising slope detection
  if (irAC > irACPrev && !risingSlope) {
    risingSlope = true;
  }
  // Peak detection (transition from rising to falling)
  else if (irAC < irACPrev && risingSlope && validBeatTiming && irAC > 50) {
    risingSlope = false;
    lastBeatTime = currentTime;
    
    // Record beat
    if (beatCount < MAX_BEATS) {
      beatTimes[beatCount] = currentTime;
      beatCount++;
      
      // Record system time of the beat
      lastBeatSystemTime = getISOTimestamp();
      
      Serial.println("❤️ Beat detected!");
      Serial.print("Beat system time: ");
      Serial.println(lastBeatSystemTime);
      
      // Calculate instantaneous BPM if we have at least 2 beats
      if (beatCount >= 2) {
        long delta = beatTimes[beatCount-1] - beatTimes[beatCount-2];
        displayedBPM = 60000 / delta;
        
        // Sanity check
        if (displayedBPM < MIN_VALID_BPM || displayedBPM > MAX_VALID_BPM) {
          displayedBPM = 0; // Invalid reading
        } else {
          Serial.print("Current BPM: ");
          Serial.println(displayedBPM);
        }
      }
      
      // Broadcast beat event via WebSocket
      DynamicJsonDocument beatDoc(256);
      beatDoc["event"] = "beat_detected";
      beatDoc["beat_time"] = lastBeatSystemTime;
      beatDoc["beat_count"] = beatCount;
      beatDoc["current_bpm"] = displayedBPM;
      
      String beatResponse;
      serializeJson(beatDoc, beatResponse);
      webSocket.broadcastTXT(beatResponse);
    }
  }
  
  // Store current AC value for next comparison
  irACPrev = irAC;
  
  // Calculate SpO2 (improved algorithm with rolling average)
  if (irValue > FINGER_PRESENCE_THRESHOLD && redValue > FINGER_PRESENCE_THRESHOLD) {
    // Create rolling arrays for red and IR values
    static long redValues[10] = {0};
    static long irValues[10] = {0};
    static int valueIndex = 0;
    static bool arrayFilled = false;
    
    // Update arrays
    redValues[valueIndex] = redValue;
    irValues[valueIndex] = irValue;
    valueIndex = (valueIndex + 1) % 10;
    
    // Check if we've filled the array at least once
    if (valueIndex == 0) {
      arrayFilled = true;
    }
    
    // Only calculate SpO2 once we have enough data
    if (arrayFilled) {
      // Calculate min and max for both red and IR to find AC component
      long redMax = redValues[0], redMin = redValues[0];
      long irMax = irValues[0], irMin = irValues[0];
      
      for (int i = 1; i < 10; i++) {
        if (redValues[i] > redMax) redMax = redValues[i];
        if (redValues[i] < redMin) redMin = redValues[i];
        if (irValues[i] > irMax) irMax = irValues[i];
        if (irValues[i] < irMin) irMin = irValues[i];
      }
      
      // Calculate R (ratio of ratios)
      float redAC = (float)(redMax - redMin);
      float redDC = (float)redMin;
      float irAC = (float)(irMax - irMin);
      float irDC = (float)irMin;
      
      // Avoid division by zero
      if (irAC > 0 && redDC > 0 && irDC > 0) {
        float R = (redAC / redDC) / (irAC / irDC);
        
        // Improved empirical formula for SpO2 calculation
        float newSpO2 = 110.0 - 25.0 * R;
        
        // Apply a weighted moving average to smooth the readings (30% new, 70% old)
        if (displayedSpO2 > 0) {
          newSpO2 = 0.3 * newSpO2 + 0.7 * displayedSpO2;
        }
        
        // Clamp to reasonable range
        if (newSpO2 > 100) newSpO2 = 100;
        if (newSpO2 < 80) newSpO2 = 80;
        
        displayedSpO2 = round(newSpO2);
      }
    }
  }
  
  // Check if measurement duration has elapsed
  if (currentTime - measurementStartTime >= MEASUREMENT_DURATION) {
    finishMeasurement();
    serverBusy = false;
  }
  
  // Show progress during measurement every 5 seconds
  if (currentTime % 5000 < 10) {
    unsigned long elapsedTime = currentTime - measurementStartTime;
    int progressPercent = (elapsedTime * 100) / MEASUREMENT_DURATION;
    int secondsRemaining = (MEASUREMENT_DURATION - elapsedTime) / 1000;
    
    Serial.print("Progress: ");
    Serial.print(progressPercent);
    Serial.print("% (");
    Serial.print(secondsRemaining);
    Serial.print(" seconds remaining), Beats detected: ");
    Serial.print(beatCount);
    Serial.print(", Current BPM: ");
    Serial.print(displayedBPM);
    Serial.print(", SpO2: ");
    Serial.println(displayedSpO2);
  }
}

void setup() {
  Serial.begin(115200);
  Serial.println("\nMAX30105 Heart Rate Monitor for ESP8266");
  
  // Connect to WiFi
  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");
  
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  
  Serial.println();
  Serial.print("Connected to WiFi. IP address: ");
  Serial.println(WiFi.localIP());
  
  // Initialize sensor
  if (!particleSensor.begin(Wire, I2C_SPEED_STANDARD)) {
    Serial.println("MAX30105 was not found. Please check wiring/power.");
    while (1);
  }
  
  Serial.println("Sensor initialized! Place your finger on the sensor.");
  
  // Configure sensor using values from config.h
  byte ledBrightness = LED_BRIGHTNESS;
  byte sampleAverage = SAMPLE_AVERAGE;
  byte ledMode = LED_MODE;
  int sampleRate = SAMPLE_RATE;
  int pulseWidth = PULSE_WIDTH;
  int adcRange = ADC_RANGE;
  
  particleSensor.setup(ledBrightness, sampleAverage, ledMode, sampleRate, pulseWidth, adcRange);
  particleSensor.setPulseAmplitudeRed(0xFF); // Maximum LED power
  particleSensor.setPulseAmplitudeIR(0xFF);  // Maximum LED power
  
  // Initialize buffer
  for (int i = 0; i < BUFFER_SIZE; i++) {
    irBuffer[i] = 0;
  }
  
  // Setup server endpoints
  server.on("/health", HTTP_GET, handleHealth);
  server.on("/beat", HTTP_GET, handleBeat);
  server.on("/readings", HTTP_GET, handleReadings);
  server.on("/results", HTTP_GET, handleReadingResults); // New endpoint for results
  server.on("/clear_results", HTTP_GET, clearMeasurementResults); // New endpoint to clear results
  
  // Start server
  server.begin();
  Serial.println("HTTP server started on port " + String(SERVER_PORT));
  
  // Start WebSocket server
  webSocket.begin();
  webSocket.onEvent(webSocketEvent);
  Serial.println("WebSocket server started on port 81");
}

void loop() {
  // Handle client requests and WebSocket events first to ensure responsiveness
  webSocket.loop();
  server.handleClient();
  
  // Only process measurements if explicitly started (not auto-started)
  if (measurementActive) {
    processRealtimeMeasurement();
  }
  
  // Only broadcast data periodically if there's an active measurement or if it's complete
  unsigned long currentTime = millis();
  if ((measurementActive || measurementComplete) && 
      (currentTime - lastBroadcastTime >= BROADCAST_INTERVAL)) {
    broadcastSensorData();
    lastBroadcastTime = currentTime;
  }
  
  // Short delay to prevent CPU hogging
  delay(10);
}