const express = require('express');
const router = express.Router();
const Location = require('../models/location');

// Haversine formula to calculate distance between two points (in kilometers)
const calculateDistance = (lat1, lon1, lat2, lon2) => {
const R = 6371; // Earth's radius in kilometers
const dLat = (lat2 - lat1) * (Math.PI / 180);
const dLon = (lon2 - lon1) * (Math.PI / 180);
const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
Math.cos(lat1 * (Math.PI / 180)) * Math.cos(lat2 * (Math.PI / 180)) *
Math.sin(dLon / 2) * Math.sin(dLon / 2);
const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
return R * c;
};

// GET /locations/nearby - Fetch nearby pharmacies and doctors
router.get('/nearby', async (req, res) => {
const { latitude, longitude } = req.query;
if (!latitude || !longitude) {
return res.status(400).json({ message: 'Latitude and longitude are required' });
}

try {
const userLat = parseFloat(latitude);
const userLon = parseFloat(longitude);
const locations = await Location.find();

const nearbyLocations = locations.map(location => {
const distance = calculateDistance(
userLat,
userLon,
location.coordinates.latitude,
location.coordinates.longitude
);
return {
name: location.name,
type: location.type,
distance: distance.toFixed(1), // Round to 1 decimal place
coordinates: location.coordinates,
};
});

// Sort by distance
nearbyLocations.sort((a, b) => a.distance - b.distance);

res.json(nearbyLocations);
} catch (error) {
console.error('Error fetching nearby locations:', error);
res.status(500).json({ message: 'Server error' });
}
});

module.exports = router;