require('dotenv').config();
const mongoose = require('mongoose');
const Location = require('../models/location');

// Validate environment variable
if (!process.env.MONGODB_URI) {
console.error('Error: MONGODB_URI is not defined in .env');
process.exit(1);
}

// Dummy locations around Cairo (lat: 30.033333, lon: 31.233334)
const locations = [
{
name: 'Cairo Pharmacy A',
type: 'Pharmacy',
coordinates: { latitude: 30.033333, longitude: 31.233334 },
address: '123 Nile St, Cairo',
},
{
name: 'Dr. Ahmed Clinic',
type: 'Doctor',
coordinates: { latitude: 30.034500, longitude: 31.234500 },
address: '456 Health Ave, Cairo',
},
{
name: 'Cairo Pharmacy B',
type: 'Pharmacy',
coordinates: { latitude: 30.032000, longitude: 31.232000 },
address: '789 Wellness Rd, Cairo',
},
{
name: 'Dr. Fatima Office',
type: 'Doctor',
coordinates: { latitude: 30.035000, longitude: 31.235000 },
address: '321 Medical Blvd, Cairo',
},
];

// Connect to MongoDB
mongoose
.connect(process.env.MONGODB_URI, {
serverSelectionTimeoutMS: 5000,
})
.then(async () => {
console.log('Connected to MongoDB');

// Clear existing locations
await Location.deleteMany({});
console.log('Cleared existing locations');

// Insert new locations
await Location.insertMany(locations);
console.log('Dummy locations added successfully:', locations);

// Close the connection
await mongoose.connection.close();
console.log('MongoDB connection closed');
process.exit(0);
})
.catch((error) => {
console.error('Error setting up locations:', error);
mongoose.connection.close();
process.exit(1);
});