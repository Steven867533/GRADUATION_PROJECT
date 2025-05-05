#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <Wire.h>
#include "MAX30105.h"
#include <ArduinoJson.h>
#include "config.h"  // Include configuration file

// WiFi credentials from config.h
const char* ssid = WIFI_SSID;
const char* password = WIFI_PASSWORD;

// Create web server on port from config.h
ESP8266WebServer server(SERVER_PORT);

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

void processMeasurement();

void resetMeasurement() {
  measurementActive = false;
  measurementComplete = false;
  beatCount = 0;
  lastBeatSystemTime = "";
}

void startMeasurement() {
  Serial.println("\n--- STARTING NEW MEASUREMENT ---");
  Serial.println("Hold your finger still for 30 seconds");
  
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
  if (beatCount >= 2) {
    // Calculate time elapsed between first and last beat
    unsigned long totalMeasurementTime = beatTimes[beatCount - 1] - beatTimes[0];
    
    // Calculate BPM: (beats-1) / minutes
    float minutesElapsed = totalMeasurementTime / 60000.0;
    calculatedBPM = (beatCount - 1) / minutesElapsed;
  } else {
    calculatedBPM = 0; // Not enough beats detected
  }
}

// Get current timestamp in ISO8601 format
String getISOTimestamp() {
  // This is a simplified version since ESP8266 doesn't have a real-time clock
  // In a real application, you would use NTP to get the actual time
  return String(millis());
}

// Handle health check endpoint
void handleHealth() {
  DynamicJsonDocument doc(256);
  doc["status"] = "UP";
  doc["timestamp"] = getISOTimestamp();
  doc["message"] = "ESP Sensor is running";
  
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
  
  String response;
  serializeJson(doc, response);
  
  server.send(200, "application/json", response);
}

// Handle readings endpoint
void handleReadings() {
  // Check if a measurement is already in progress
  if (measurementActive) {
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
  
  // Process the measurement (blocking call)
  processMeasurement();
  
  // Return the results
  DynamicJsonDocument doc(256);
  doc["status"] = "success";
  doc["heartRate"] = round(calculatedBPM * 10) / 10.0;
  doc["spo2"] = round(displayedSpO2 * 10) / 10.0;
  doc["beatsDetected"] = beatCount;
  doc["timestamp"] = getISOTimestamp();
  
  String response;
  serializeJson(doc, response);
  
  server.send(200, "application/json", response);
}

// Process the measurement
void processMeasurement() {
  unsigned long startTime = millis();
  
  while (measurementActive) {
    // Read from sensor
    long irValue = particleSensor.getIR();
    long redValue = particleSensor.getRed();

    // Check if finger is placed on sensor
    if (irValue < FINGER_PRESENCE_THRESHOLD) { // Threshold from config.h
      resetMeasurement();
      Serial.println("No finger detected. Place finger on sensor.");
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
      }
    }
    
    // Store current AC value for next comparison
    irACPrev = irAC;
    
    // Calculate SpO2 (simplified approximation)
    if (irValue > FINGER_PRESENCE_THRESHOLD && redValue > FINGER_PRESENCE_THRESHOLD) {
      float ratio = (float)redValue / (float)irValue;
      displayedSpO2 = 110 - 25 * ratio;
      
      // Clamp to reasonable range
      if (displayedSpO2 > 100) displayedSpO2 = 100;
      if (displayedSpO2 < 80) displayedSpO2 = 80;
    }
    
    // Show progress during measurement every 3 seconds
    if (millis() % 3000 < 10) {
      unsigned long elapsedTime = currentTime - measurementStartTime;
      int progressPercent = (elapsedTime * 100) / MEASUREMENT_DURATION;
      
      Serial.print("Progress: ");
      Serial.print(progressPercent);
      Serial.print("%, Beats detected: ");
      Serial.print(beatCount);
      Serial.print(", Current BPM: ");
      Serial.print(displayedBPM);
      Serial.print(", SpO2: ");
      Serial.println(displayedSpO2);
    }
    
    // Check if measurement duration has elapsed
    if (currentTime - measurementStartTime >= MEASUREMENT_DURATION) {
      finishMeasurement();
    }
    
    // Handle WiFi and server clients
    server.handleClient();
    
    // Short delay between readings
    delay(10);
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
  
  // Start server
  server.begin();
  Serial.println("HTTP server started");
}

void loop() {
  // Handle client requests
  server.handleClient();
  
  // If no measurement is active, just check for finger presence
  if (!measurementActive && !measurementComplete) {
    long irValue = particleSensor.getIR();
    
    // Check if finger is placed on sensor (just for debug info)
    if (irValue > FINGER_PRESENCE_THRESHOLD && millis() % 2000 < 10) {
      Serial.println("Finger detected. Use /readings endpoint to start measurement.");
    }
  }
  
  // If measurement is complete, show final results
  if (measurementComplete) {
    Serial.println("\n--- FINAL MEASUREMENT RESULTS ---");
    Serial.print("Heart Rate: ");
    Serial.print(calculatedBPM);
    Serial.print(" BPM (based on ");
    Serial.print(beatCount);
    Serial.println(" beats)");
    
    Serial.print("SpO2 Estimate: ");
    Serial.print(displayedSpO2);
    Serial.println("%");
    
    Serial.println("\nPlace finger on sensor and use /readings endpoint to start a new measurement.");
    Serial.println("------------------------------");
    
    // Reset for next measurement
    measurementComplete = false;
    
    // Wait a bit before allowing a new measurement
    delay(1000);
  }
  
  // Short delay to prevent CPU hogging
  delay(10);
}