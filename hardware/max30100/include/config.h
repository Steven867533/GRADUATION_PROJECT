// ESP8266 Sensor Configuration File

#ifndef CONFIG_H
#define CONFIG_H


#define WIFI_SSID "steven"      
#define WIFI_PASSWORD "SSSTTTEEEVVVEEENNN"  


#define SERVER_PORT 80  


#define LED_BRIGHTNESS 0xFF  
#define SAMPLE_AVERAGE 8     
#define LED_MODE 2           
#define SAMPLE_RATE 100      
#define PULSE_WIDTH 1600     
#define ADC_RANGE 16384      


#define MEASUREMENT_DURATION 30000  
#define MIN_BEAT_INTERVAL 250      
#define MAX_BEATS 120              
#define BUFFER_SIZE 100            


#define FINGER_PRESENCE_THRESHOLD 30000  
#define MIN_VALID_BPM 40                 
#define MAX_VALID_BPM 220                

#endif // CONFIG_H