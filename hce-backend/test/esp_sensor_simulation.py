import numpy as np
from flask import Flask, jsonify
import time
import threading
import random
from flask_cors import CORS

app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})  # Allow all origins for testing

# Timing variables
MEASUREMENT_DURATION = 30  # 30 seconds
measurement_active = False
measurement_complete = False
measurement_start_time = 0

# Beat detection variables
MAX_BEATS = 120
beat_times = [0] * MAX_BEATS
beat_count = 0
calculated_bpm = 0
last_beat_system_time = None  # System time of the last beat (UTC)

# Signal processing
BUFFER_SIZE = 100
ir_buffer = [0] * BUFFER_SIZE
buffer_index = 0
ir_dc = 0  # DC component (baseline)
ir_ac_prev = 0  # Previous AC value
rising_slope = False
last_beat_time = 0
MIN_BEAT_INTERVAL = 0.25  # 250ms (240 BPM max)

# Display variables
displayed_bpm = 0
displayed_spo2 = 0

# Simulated sensor state
finger_detected = False
simulated_time = 0

# Lock for thread safety
lock = threading.Lock()

def reset_measurement():
    global measurement_active, measurement_complete, beat_count, simulated_time, last_beat_system_time
    with lock:
        measurement_active = False
        measurement_complete = False
        beat_count = 0
        simulated_time = 0
        last_beat_system_time = None

def start_measurement():
    global measurement_active, measurement_complete, measurement_start_time
    global beat_count, ir_ac_prev, rising_slope, simulated_time, last_beat_system_time
    print("\n--- STARTING NEW MEASUREMENT ---")
    print("Simulating measurement for 30 seconds")
    with lock:
        # Reset variables
        beat_count = 0
        calculated_bpm = 0
        ir_ac_prev = 0
        rising_slope = False
        simulated_time = 0
        last_beat_system_time = None

        # Set timing
        measurement_start_time = time.time()
        measurement_active = True
        measurement_complete = False

def finish_measurement():
    global measurement_active, measurement_complete, calculated_bpm
    with lock:
        measurement_active = False
        measurement_complete = True

        # Calculate accurate BPM based on collected data
        if beat_count >= 2:
            # Calculate time elapsed between first and last beat
            total_measurement_time = beat_times[beat_count - 1] - beat_times[0]
            # Calculate BPM: (beats-1) / minutes
            minutes_elapsed = total_measurement_time / 60.0
            calculated_bpm = (beat_count - 1) / minutes_elapsed
        else:
            calculated_bpm = 0  # Not enough beats detected

def simulate_ir_red_values(t):
    """
    Simulate IR and red values using a sinusoidal wave to mimic heartbeat.
    Frequency is set to ~1 Hz (60 BPM) with some variation.
    """
    # Simulate a heart rate between 60 and 100 BPM
    bpm = random.uniform(60, 100)
    freq = bpm / 60.0  # Hz
    # IR signal: sinusoidal wave with DC offset and noise
    ir_amplitude = 5000
    ir_dc = 50000  # DC component
    ir_noise = random.uniform(-1000, 1000)
    ir_value = ir_dc + ir_amplitude * np.sin(2 * np.pi * freq * t) + ir_noise

    # Red signal: slightly different amplitude for SpO2 calculation
    red_amplitude = 4800
    red_noise = random.uniform(-1000, 1000)
    red_value = ir_dc + red_amplitude * np.sin(2 * np.pi * freq * t) + red_noise

    return ir_value, red_value

def process_measurement():
    global buffer_index, ir_dc, ir_ac_prev, rising_slope, last_beat_time
    global beat_count, displayed_bpm, displayed_spo2, simulated_time, last_beat_system_time

    sample_rate = 100  # 100 samples per second
    sample_interval = 1.0 / sample_rate

    while measurement_active:
        with lock:
            current_time = simulated_time
            # Simulate IR and red values
            ir_value, red_value = simulate_ir_red_values(current_time)

            # Check if finger is detected (simulated as always detected for now)
            if ir_value < 30000:
                reset_measurement()
                print("No finger detected (simulated).")
                return

            # Update buffer
            ir_buffer[buffer_index] = ir_value
            buffer_index = (buffer_index + 1) % BUFFER_SIZE

            # Calculate DC component (baseline) - moving average
            ir_dc = sum(ir_buffer) / BUFFER_SIZE

            # Extract AC component (pulsatile)
            ir_ac = ir_value - ir_dc

            # Beat detection using slope detection
            valid_beat_timing = (current_time - last_beat_time) > MIN_BEAT_INTERVAL

            # Rising slope detection
            if ir_ac > ir_ac_prev and not rising_slope:
                rising_slope = True
            # Peak detection (transition from rising to falling)
            elif ir_ac < ir_ac_prev and rising_slope and valid_beat_timing and ir_ac > 50:
                rising_slope = False
                last_beat_time = current_time

                # Record beat
                if beat_count < MAX_BEATS:
                    beat_times[beat_count] = current_time
                    beat_count += 1

                    # Record system time of the beat
                    last_beat_system_time = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())

                    print("❤️ Beat detected!")
                    print(f"Beat system time: {last_beat_system_time}")

                    # Calculate instantaneous BPM if we have at least 2 beats
                    if beat_count >= 2:
                        delta = beat_times[beat_count-1] - beat_times[beat_count-2]
                        displayed_bpm = 60.0 / delta

                        # Sanity check
                        if displayed_bpm < 40 or displayed_bpm > 220:
                            displayed_bpm = 0  # Invalid reading
                        else:
                            print(f"Current BPM: {displayed_bpm:.1f}")

            # Store current AC value for next comparison
            ir_ac_prev = ir_ac

            # Calculate SpO2 (simplified approximation)
            if ir_value > 30000 and red_value > 30000:
                ratio = red_value / ir_value
                displayed_spo2 = 110 - 25 * ratio

                # Clamp to reasonable range
                if displayed_spo2 > 100:
                    displayed_spo2 = 100
                if displayed_spo2 < 80:
                    displayed_spo2 = 80

            # Show progress every 3 seconds
            if int(current_time * 1000) % 3000 < 10:
                elapsed_time = current_time - measurement_start_time
                progress_percent = (elapsed_time * 100) / MEASUREMENT_DURATION
                print(f"Progress: {progress_percent:.1f}%, Beats detected: {beat_count}, "
                      f"Current BPM: {displayed_bpm:.1f}, SpO2: {displayed_spo2:.1f}")

            # Check if measurement duration has elapsed
            if current_time - measurement_start_time >= MEASUREMENT_DURATION:
                finish_measurement()

            simulated_time += sample_interval

        # Simulate delay between samples
        time.sleep(sample_interval)

@app.route('/health')
def health():
    return jsonify({
        "status": "UP",
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
        "message": "ESP Sensor Simulator is running"
    })

@app.route('/readings')
def get_readings():
    global measurement_active, measurement_complete

    # Check if a measurement is already in progress
    if measurement_active:
        return jsonify({
            "status": "error",
            "message": "Measurement in progress. Please wait."
        }), 400

    # Reset and start a new measurement
    reset_measurement()
    start_measurement()

    # Run measurement in a separate thread
    threading.Thread(target=process_measurement, daemon=True).start()

    # Wait for measurement to complete
    while not measurement_complete:
        time.sleep(0.1)

    # Return the results
    return jsonify({
        "status": "success",
        "heartRate": round(calculated_bpm, 1),
        "spo2": round(displayed_spo2, 1),
        "beatsDetected": beat_count,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
    })

@app.route('/beat')
def get_beat():
    with lock:
        return jsonify({
            "lastBeatTime": last_beat_system_time,
            "measurementActive": measurement_active,
            "beatsDetected": beat_count
        })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)