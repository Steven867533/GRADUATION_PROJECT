// ESP8266 Sensor Configuration File

#ifndef CONFIG_H
#define CONFIG_H


#define WIFI_SSID "Redmi 10C"      
#define WIFI_PASSWORD "sandra123"  


#define SERVER_PORT 80  
#define WEBSOCKET_PORT 81  // Added WebSocket port


#define LED_BRIGHTNESS 0xFF  
#define SAMPLE_AVERAGE 8     
#define LED_MODE 2           
#define SAMPLE_RATE 100      
#define PULSE_WIDTH 1600     
#define ADC_RANGE 16384      


#define MEASUREMENT_DURATION 60000  // 60 seconds of measurement
#define MIN_BEAT_INTERVAL 250      
#define MAX_BEATS 250              // Increased to accommodate 60 seconds of measurement
#define BUFFER_SIZE 150            // Increased buffer size for better accuracy


#define FINGER_PRESENCE_THRESHOLD 25000  // Slightly lower threshold for better finger detection
#define MIN_VALID_BPM 40                 
#define MAX_VALID_BPM 220               


#define BROADCAST_INTERVAL 500  // Broadcast sensor data every 500ms

#endif // CONFIG_H