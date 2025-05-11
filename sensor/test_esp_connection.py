#!/usr/bin/env python3
"""
ESP8266 Connection Test Script

This script tests the connection to an ESP8266 running the heart rate sensor code.
It attempts to connect to all the ESP8266 endpoints and verifies the responses.
"""

import requests
import json
import time
import argparse

def test_health(base_url):
    """Test the health endpoint"""
    print("\n1. Testing /health endpoint...")
    try:
        response = requests.get(f"{base_url}/health", timeout=5)
        print(f"Status code: {response.status_code}")
        if response.status_code == 200:
            data = response.json()
            print(f"Response: {json.dumps(data, indent=2)}")
            if data.get('status') == 'UP':
                print("✅ Health check successful!")
                return True
            else:
                print("❌ Health check failed: Status not 'UP'")
                return False
        else:
            print(f"❌ Health check failed: Unexpected status code {response.status_code}")
            return False
    except requests.exceptions.RequestException as e:
        print(f"❌ Health check failed: {e}")
        return False

def test_beat(base_url):
    """Test the beat endpoint"""
    print("\n2. Testing /beat endpoint...")
    try:
        response = requests.get(f"{base_url}/beat", timeout=5)
        print(f"Status code: {response.status_code}")
        if response.status_code == 200:
            data = response.json()
            print(f"Response: {json.dumps(data, indent=2)}")
            print("✅ Beat endpoint test successful!")
            return True
        else:
            print(f"❌ Beat endpoint test failed: Unexpected status code {response.status_code}")
            return False
    except requests.exceptions.RequestException as e:
        print(f"❌ Beat endpoint test failed: {e}")
        return False

def test_readings(base_url):
    """Test the readings endpoint"""
    print("\n3. Testing /readings endpoint...")
    print("Note: This will start a 30-second measurement. Please place your finger on the sensor.")
    input("Press Enter to continue...")
    
    try:
        print("Starting measurement...")
        start_time = time.time()
        response = requests.get(f"{base_url}/readings", timeout=40)  # Longer timeout for measurement
        elapsed_time = time.time() - start_time
        
        print(f"Measurement completed in {elapsed_time:.1f} seconds")
        print(f"Status code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"Response: {json.dumps(data, indent=2)}")
            if data.get('status') == 'success':
                print("✅ Readings test successful!")
                print(f"Heart Rate: {data.get('heartRate')} BPM")
                print(f"SpO2: {data.get('spo2')}%")
                return True
            else:
                print("❌ Readings test failed: Status not 'success'")
                return False
        else:
            print(f"❌ Readings test failed: Unexpected status code {response.status_code}")
            return False
    except requests.exceptions.RequestException as e:
        print(f"❌ Readings test failed: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(description='Test ESP8266 heart rate sensor connection')
    parser.add_argument('--url', default='http://192.168.1.100', help='Base URL of the ESP8266 (default: http://192.168.1.100)')
    parser.add_argument('--skip-readings', action='store_true', help='Skip the readings test (which takes 30 seconds)')
    args = parser.parse_args()
    
    print(f"Testing connection to ESP8266 at {args.url}")
    
    # Test health endpoint
    health_ok = test_health(args.url)
    
    # Test beat endpoint
    beat_ok = test_beat(args.url)
    
    # Test readings endpoint (unless skipped)
    readings_ok = True
    if not args.skip_readings:
        readings_ok = test_readings(args.url)
    else:
        print("\n3. Skipping /readings test as requested")
    
    # Summary
    print("\n=== TEST SUMMARY ===")
    print(f"Health endpoint: {'✅ PASSED' if health_ok else '❌ FAILED'}")
    print(f"Beat endpoint: {'✅ PASSED' if beat_ok else '❌ FAILED'}")
    if not args.skip_readings:
        print(f"Readings endpoint: {'✅ PASSED' if readings_ok else '❌ FAILED'}")
    else:
        print("Readings endpoint: SKIPPED")
    
    if health_ok and beat_ok and (readings_ok or args.skip_readings):
        print("\n✅ All tests passed! Your ESP8266 is working correctly.")
    else:
        print("\n❌ Some tests failed. Please check your ESP8266 setup.")

if __name__ == "__main__":
    main()