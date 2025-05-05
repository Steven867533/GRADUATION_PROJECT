#!/bin/bash

# Configuration
BACKEND_URL="http://localhost:5000"
PORT=5000

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Function to log messages
log() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if a command was successful
check_status() {
  if [ $? -eq 0 ]; then
    log "${GREEN}SUCCESS: $1${NC}"
  else
    log "${RED}FAILURE: $1${NC}"
    cleanup
    exit 1
  fi
}

# Cleanup function to stop the server
cleanup() {
  log "Shutting down server..."
  if [ ! -z "$SERVER_PID" ] && ps -p $SERVER_PID > /dev/null; then
    kill $SERVER_PID
    wait $SERVER_PID 2>/dev/null
    log "Server stopped"
  else
    log "Server process $SERVER_PID already stopped"
  fi
}

# Trap to ensure cleanup on script exit
trap cleanup EXIT

# Step 1: Start the backend server
log "Starting backend server on port $PORT..."
cd "$(dirname "$0")/.."
# Export environment variables from .env
if [ ! -f .env ]; then
  log "${RED}ERROR: .env file not found${NC}"
  exit 1
fi
set -a
source .env
set +a
node server.js &
SERVER_PID=$!
sleep 5 # Wait for the server to start
log "Server PID: $SERVER_PID"
curl -s -o /dev/null -w "%{http_code}" $BACKEND_URL/health | grep -q 200
check_status "Backend server started and healthy"

# Step 2: Run the setup_locations.js script to populate locations
log "Setting up dummy locations..."
node scripts/setup_locations.js
check_status "Locations setup completed"

# Step 3: Create test users (Doctor, Companion, Patient)
# First create doctor
log "Creating test doctor..."
DOCTOR_PHONE="+20123456789"
DOCTOR_RESPONSE=$(curl -s -X POST $BACKEND_URL/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"name":"Dr. Ahmed","email":"doctor@example.com","password":"SecurePass123!","phoneNumber":"'"$DOCTOR_PHONE"'","birthdate":"1970-03-20","role":"Doctor"}')
echo "$DOCTOR_RESPONSE"
DOCTOR_TOKEN=$(echo "$DOCTOR_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
DOCTOR_ID=$(echo "$DOCTOR_RESPONSE" | grep -o '"userId":"[^"]*' | cut -d'"' -f4)
DOCTOR_PHONE="+20123456789"  # Add this line to define doctor's phone
log "Doctor Token: $DOCTOR_TOKEN"
log "Doctor ID: $DOCTOR_ID"
[ ! -z "$DOCTOR_TOKEN" ] && [ ! -z "$DOCTOR_ID" ]
check_status "Doctor created successfully"

# Create companion (without patientId initially)
log "Creating test companion..."
COMPANION_PHONE="+20123456791"
COMPANION_RESPONSE=$(curl -s -X POST $BACKEND_URL/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"name":"Sara Ali","email":"companion@example.com","password":"SecurePass123!","phoneNumber":"'"$COMPANION_PHONE"'","birthdate":"1985-05-15","role":"Companion"}')
echo "$COMPANION_RESPONSE"
COMPANION_TOKEN=$(echo "$COMPANION_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
COMPANION_ID=$(echo "$COMPANION_RESPONSE" | grep -o '"userId":"[^"]*' | cut -d'"' -f4)
COMPANION_PHONE="+20123456791"  # Add this line to define companion's phone
log "Companion Token: $COMPANION_TOKEN"
log "Companion ID: $COMPANION_ID"
[ ! -z "$COMPANION_TOKEN" ] && [ ! -z "$COMPANION_ID" ]
check_status "Companion created successfully"

# Create patient (without doctorId and companionId initially)
log "Creating test patient..."
PATIENT_PHONE="+20123456790"
PATIENT_RESPONSE=$(curl -s -X POST $BACKEND_URL/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"name":"Ali Hassan","email":"patient@example.com","password":"SecurePass123!","phoneNumber":"'"$PATIENT_PHONE"'","birthdate":"1990-01-01","role":"Patient","bloodPressureType":"Average"}')
echo "$PATIENT_RESPONSE"
PATIENT_TOKEN=$(echo "$PATIENT_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
PATIENT_ID=$(echo "$PATIENT_RESPONSE" | grep -o '"userId":"[^"]*' | cut -d'"' -f4)
PATIENT_PHONE="+20123456790"  # Add this line to define patient's phone
log "Patient Token: $PATIENT_TOKEN"
log "Patient ID: $PATIENT_ID"
[ ! -z "$PATIENT_TOKEN" ] && [ ! -z "$PATIENT_ID" ]
check_status "Patient created successfully"

# Update companion with patientId
log "Updating companion with patient ID..."
COMPANION_UPDATE_RESPONSE=$(curl -s -X PUT $BACKEND_URL/users/$COMPANION_ID \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $COMPANION_TOKEN" \
  -d '{"patientId":"'"$PATIENT_ID"'"}')
echo "$COMPANION_UPDATE_RESPONSE"
check_status "Companion updated with patient ID"

# Update patient with doctorId and companionId
log "Updating patient with doctor and companion IDs..."
PATIENT_UPDATE_RESPONSE=$(curl -s -X PUT $BACKEND_URL/users/$PATIENT_ID \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $PATIENT_TOKEN" \
  -d '{"doctorId":"'"$DOCTOR_ID"'","companionId":"'"$COMPANION_ID"'"}')
echo "$PATIENT_UPDATE_RESPONSE"
check_status "Patient updated with doctor and companion IDs"

# Update companion with patient phone number instead of ID
log "Updating companion with patient phone number..."
COMPANION_UPDATE_RESPONSE=$(curl -s -X PUT $BACKEND_URL/users/$COMPANION_ID \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $COMPANION_TOKEN" \
  -d '{"patientPhoneNumber":"'"$PATIENT_PHONE"'"}')
echo "$COMPANION_UPDATE_RESPONSE"
check_status "Companion updated with patient phone number"

# Update patient with doctor and companion phone numbers instead of IDs
log "Updating patient with doctor and companion phone numbers..."
PATIENT_UPDATE_RESPONSE=$(curl -s -X PUT $BACKEND_URL/users/$PATIENT_ID \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $PATIENT_TOKEN" \
  -d '{"doctorPhoneNumber":"'"$DOCTOR_PHONE"'","companionPhoneNumber":"'"$COMPANION_PHONE"'"}')
echo "$PATIENT_UPDATE_RESPONSE"
check_status "Patient updated with doctor and companion phone numbers"

# Step 4: Log in as the patient
log "Logging in as patient..."
LOGIN_RESPONSE=$(curl -s -X POST $BACKEND_URL/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"patient@example.com","password":"SecurePass123!"}')
echo "$LOGIN_RESPONSE"
TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
log "Login Token: $TOKEN"
[ ! -z "$TOKEN" ]
check_status "Patient login successful"

# Step 5: Test fetching user profile
log "Fetching patient profile..."
PROFILE_RESPONSE=$(curl -s -X GET $BACKEND_URL/users/me \
  -H "Authorization: Bearer $TOKEN")
echo "$PROFILE_RESPONSE"
echo "$PROFILE_RESPONSE" | grep -q '"email":"patient@example.com"'
check_status "User profile fetched successfully"

# Step 6: Test fetching nearby locations (using Cairo coordinates)
log "Fetching nearby locations..."
LOCATIONS_RESPONSE=$(curl -s -X GET "$BACKEND_URL/locations/nearby?latitude=30.033333&longitude=31.233334")
echo "$LOCATIONS_RESPONSE"
echo "$LOCATIONS_RESPONSE" | grep -q '"name":"Cairo Pharmacy A"'
check_status "Nearby locations fetched successfully"

# Step 7: Test sending a message to the doctor
log "Sending a message to the doctor..."
MESSAGE_RESPONSE=$(curl -s -X POST $BACKEND_URL/messages \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"recipientId":"'"$DOCTOR_ID"'","content":"Test message from patient"}')
echo "$MESSAGE_RESPONSE"
echo "$MESSAGE_RESPONSE" | grep -q '"message":"Message sent"'
check_status "Message sent successfully"

# Step 8: Test sending a message to the companion
log "Sending a message to the companion..."
COMPANION_MESSAGE_RESPONSE=$(curl -s -X POST $BACKEND_URL/messages \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"recipientId":"'"$COMPANION_ID"'","content":"Test message from patient to companion"}')
echo "$COMPANION_MESSAGE_RESPONSE"
echo "$COMPANION_MESSAGE_RESPONSE" | grep -q '"message":"Message sent"'
check_status "Message to companion sent successfully"

# Step 9: Clean up
log "All tests passed!"
cleanup
exit 0