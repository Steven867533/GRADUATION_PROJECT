#!/bin/bash

# Define API base URL
API_BASE_URL="http://localhost:5000"

# Dummy data for patient
PATIENT_NAME="John Doe"
PATIENT_EMAIL="john.doe@example.com"
PATIENT_PASSWORD="SecurePass123!"
PATIENT_PHONE="+1234567890"
PATIENT_BIRTHDATE="1950-01-01"
PATIENT_ROLE="Patient"
PATIENT_BP_TYPE="High"

# Dummy data for companion
COMPANION_NAME="Jane Smith"
COMPANION_EMAIL="jane.smith@example.com"
COMPANION_PASSWORD="SecurePass456!"
COMPANION_PHONE="+0987654321"
COMPANION_BIRTHDATE="1980-05-15"
COMPANION_ROLE="Companion"

# Step 1: Add a dummy patient
echo "Adding dummy patient..."
PATIENT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$PATIENT_NAME\", \"email\":\"$PATIENT_EMAIL\", \"password\":\"$PATIENT_PASSWORD\", \"phoneNumber\":\"$PATIENT_PHONE\", \"birthdate\":\"$PATIENT_BIRTHDATE\", \"role\":\"$PATIENT_ROLE\", \"bloodPressureType\":\"$PATIENT_BP_TYPE\"}" \
  "$API_BASE_URL/auth/signup")

# Extract HTTP status code and response body
PATIENT_HTTP_CODE=$(echo "$PATIENT_RESPONSE" | tail -n1)
PATIENT_BODY=$(echo "$PATIENT_RESPONSE" | sed -e '$d')

# Check if patient signup was successful (HTTP 201 and token present)
if [ "$PATIENT_HTTP_CODE" -eq 201 ] && echo "$PATIENT_BODY" | grep -q '"token":"'; then
  PATIENT_TOKEN=$(echo "$PATIENT_BODY" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
  echo "Patient added successfully: $PATIENT_NAME ($PATIENT_EMAIL)"
  echo "Patient signup token: $PATIENT_TOKEN"
else
  echo "Failed to add patient: $PATIENT_BODY"
  exit 1
fi

# Step 2: Add a companion linked to the patient
echo "Adding dummy companion..."
COMPANION_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$COMPANION_NAME\", \"email\":\"$COMPANION_EMAIL\", \"password\":\"$COMPANION_PASSWORD\", \"phoneNumber\":\"$COMPANION_PHONE\", \"birthdate\":\"$COMPANION_BIRTHDATE\", \"role\":\"$COMPANION_ROLE\", \"patientPhoneNumber\":\"$PATIENT_PHONE\"}" \
  "$API_BASE_URL/auth/signup")

# Extract HTTP status code and response body
COMPANION_HTTP_CODE=$(echo "$COMPANION_RESPONSE" | tail -n1)
COMPANION_BODY=$(echo "$COMPANION_RESPONSE" | sed -e '$d')

# Check if companion signup was successful (HTTP 201 and token present)
if [ "$COMPANION_HTTP_CODE" -eq 201 ] && echo "$COMPANION_BODY" | grep -q '"token":"'; then
  COMPANION_TOKEN=$(echo "$COMPANION_BODY" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
  echo "Companion added successfully: $COMPANION_NAME ($COMPANION_EMAIL), linked to patient phone $PATIENT_PHONE"
  echo "Companion signup token: $COMPANION_TOKEN"
else
  echo "Failed to add companion: $COMPANION_BODY"
  exit 1
fi

# Step 3: Test login for patient
echo "Testing login for patient..."
PATIENT_LOGIN_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$PATIENT_EMAIL\", \"password\":\"$PATIENT_PASSWORD\"}" \
  "$API_BASE_URL/auth/login")

# Extract HTTP status code and response body
PATIENT_LOGIN_HTTP_CODE=$(echo "$PATIENT_LOGIN_RESPONSE" | tail -n1)
PATIENT_LOGIN_BODY=$(echo "$PATIENT_LOGIN_RESPONSE" | sed -e '$d')

# Check if patient login was successful (HTTP 200 and token present)
if [ "$PATIENT_LOGIN_HTTP_CODE" -eq 200 ] && echo "$PATIENT_LOGIN_BODY" | grep -q '"token":"'; then
  PATIENT_LOGIN_TOKEN=$(echo "$PATIENT_LOGIN_BODY" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
  echo "Patient login successful! Token: $PATIENT_LOGIN_TOKEN"
else
  echo "Patient login failed: $PATIENT_LOGIN_BODY"
  exit 1
fi

# Step 4: Test login for companion
echo "Testing login for companion..."
COMPANION_LOGIN_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$COMPANION_EMAIL\", \"password\":\"$COMPANION_PASSWORD\"}" \
  "$API_BASE_URL/auth/login")

# Extract HTTP status code and response body
COMPANION_LOGIN_HTTP_CODE=$(echo "$COMPANION_LOGIN_RESPONSE" | tail -n1)
COMPANION_LOGIN_BODY=$(echo "$COMPANION_LOGIN_RESPONSE" | sed -e '$d')

# Check if companion login was successful (HTTP 200 and token present)
if [ "$COMPANION_LOGIN_HTTP_CODE" -eq 200 ] && echo "$COMPANION_LOGIN_BODY" | grep -q '"token":"'; then
  COMPANION_LOGIN_TOKEN=$(echo "$COMPANION_LOGIN_BODY" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
  echo "Companion login successful! Token: $COMPANION_LOGIN_TOKEN"
else
  echo "Companion login failed: $COMPANION_LOGIN_BODY"
  exit 1
fi

echo "All operations completed successfully!"