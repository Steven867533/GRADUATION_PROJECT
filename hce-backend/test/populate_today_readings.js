// Script to populate today's readings with normal values for a test patient
const axios = require('axios');
const BASE_URL = process.env.BACKEND_URL || 'http://localhost:5000';
const TEST_PATIENT_EMAIL = process.env.TEST_PATIENT_EMAIL || 'patient@example.com';
const TEST_PATIENT_PASSWORD = process.env.TEST_PATIENT_PASSWORD || 'SecurePass123!';

async function loginAndGetToken() {
  const res = await axios.post(`${BASE_URL}/auth/login`, {
    email: TEST_PATIENT_EMAIL,
    password: TEST_PATIENT_PASSWORD
  });
  return res.data.token;
}

async function getPatientId(token) {
  const res = await axios.get(`${BASE_URL}/users/me`, {
    headers: { Authorization: `Bearer ${token}` }
  });
  return res.data._id;
}

async function addReading(token, patientId, reading) {
  await axios.post(`${BASE_URL}/readings`, {
    ...reading,
    userId: patientId
  }, {
    headers: { Authorization: `Bearer ${token}` }
  });
}

async function main() {
  try {
    const token = await loginAndGetToken();
    const patientId = await getPatientId(token);
    const now = new Date();
    // Normal values
    const readings = [
      { systolic: 120, diastolic: 80, heartRate: 72, spo2: 98, timestamp: now },
      { systolic: 118, diastolic: 78, heartRate: 70, spo2: 97, timestamp: now },
      { systolic: 122, diastolic: 82, heartRate: 74, spo2: 99, timestamp: now }
    ];
    for (const reading of readings) {
      await addReading(token, patientId, reading);
      console.log('Added reading:', reading);
    }
    console.log('Populated today\'s readings successfully.');
  } catch (err) {
    console.error('Error populating readings:', err.response ? err.response.data : err.message);
    process.exit(1);
  }
}

main();