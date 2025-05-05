#include <Arduino.h>


#include <Wire.h>
#include "MAX30105.h"

MAX30105 particleSensor;

// Timing variables
unsigned long measurementStartTime = 0;
const unsigned long MEASUREMENT_DURATION = 30000; // 30 seconds
bool measurementActive = false;
bool measurementComplete = false;

// Beat detection variables
const int MAX_BEATS = 120;
unsigned long beatTimes[MAX_BEATS];
int beatCount = 0;
float calculatedBPM = 0;

// Signal processing
const int BUFFER_SIZE = 100;
long irBuffer[BUFFER_SIZE];
int bufferIndex = 0;
long irDC = 0;    // DC component (baseline)
long irACPrev = 0; // Previous AC value
bool risingSlope = false;
bool beatDetected = false;
unsigned long lastBeatTime = 0;
const unsigned long MIN_BEAT_INTERVAL = 250; // 250ms (240 BPM max)

// Display variables
int displayedBPM = 0;
int displayedSpO2 = 0;

// Debug mode (set to true to see more detailed output)
const bool DEBUG = true;

void resetMeasurement();
void startMeasurement();
void finishMeasurement();

void setup() {
  Serial.begin(9600);
  Serial.println("MAX30100 Optimized Heart Rate Monitor");

  // Initialize sensor
  if (!particleSensor.begin(Wire, I2C_SPEED_STANDARD)) { // Use standard I2C speed for MAX30100
    Serial.println("MAX30100 was not found. Please check wiring/power.");
    while (1);
  }
  
  Serial.println("Sensor initialized! Place your finger on the sensor.");

  // Configure sensor specifically for MAX30100
  byte ledBrightness = 0xFF; // Full brightness for better signal
  byte sampleAverage = 8;    // Average 8 samples for better stability
  byte ledMode = 2;          // 2 = Red + IR
  int sampleRate = 100;      // 100 samples per second works better for MAX30100
  int pulseWidth = 1600;     // Maximum pulse width for more light
  int adcRange = 16384;      // 16-bit ADC range
  
  particleSensor.setup(ledBrightness, sampleAverage, ledMode, sampleRate, pulseWidth, adcRange);
  particleSensor.setPulseAmplitudeRed(0xFF); // Maximum LED power
  particleSensor.setPulseAmplitudeIR(0xFF);  // Maximum LED power
  
  // Initialize buffer
  for (int i = 0; i < BUFFER_SIZE; i++) {
    irBuffer[i] = 0;
  }
}

void loop() {
  // Read from sensor
  long irValue = particleSensor.getIR();
  long redValue = particleSensor.getRed();

  // Check if finger is placed on sensor
  if (irValue < 30000) { // Lower threshold for detection
    resetMeasurement();
    Serial.println("No finger detected. Place finger on sensor.");
    delay(1000);
    return;
  }
  
  // Start measurement when finger is detected
  if (!measurementActive && !measurementComplete) {
    startMeasurement();
    // Initialize buffer with current value
    for (int i = 0; i < BUFFER_SIZE; i++) {
      irBuffer[i] = irValue;
    }
    irDC = irValue;
  }
  
  // Process signal and detect beats during measurement
  if (measurementActive) {
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
        
        // Print beat marker
        Serial.println("❤️ Beat detected!");
        
        // Calculate instantaneous BPM if we have at least 2 beats
        if (beatCount >= 2) {
          long delta = beatTimes[beatCount-1] - beatTimes[beatCount-2];
          displayedBPM = 60000 / delta;
          
          // Sanity check
          if (displayedBPM < 40 || displayedBPM > 220) {
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
    
    // Debug output
    if (DEBUG && currentTime % 500 < 10) {
      Serial.print("IR: ");
      Serial.print(irValue);
      Serial.print(", DC: ");
      Serial.print(irDC);
      Serial.print(", AC: ");
      Serial.print(irAC);
      Serial.print(", Rising: ");
      Serial.println(risingSlope ? "Yes" : "No");
    }
    
    // Check if measurement duration has elapsed
    if (currentTime - measurementStartTime >= MEASUREMENT_DURATION) {
      finishMeasurement();
    }
    
    // Calculate SpO2 (simplified approximation)
    if (irValue > 30000 && redValue > 30000) {
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
  }
  
  // Display final results if measurement is complete
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
    
    Serial.println("\nPlace finger on sensor to start a new measurement.");
    Serial.println("------------------------------");
    
    // Wait before allowing a new measurement
    delay(5000);
    measurementComplete = false;
  }
  
  delay(10); // Short delay between readings
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

void resetMeasurement() {
  measurementActive = false;
  measurementComplete = false;
  beatCount = 0;
}