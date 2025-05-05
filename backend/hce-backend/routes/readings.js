const express = require('express');
const router = express.Router();
const Reading = require('../models/reading');
const authMiddleware = require('../middleware/auth');

// Save a new reading
router.post('/', authMiddleware, async (req, res) => {
  try {
    const { heartRate, spo2, latitude, longitude } = req.body;
    const reading = new Reading({
      userId: req.user.userId,
      heartRate,
      spo2,
      location: { latitude, longitude },
    });
    await reading.save();
    res.status(201).json(reading);
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
});

// Fetch readings for a user by date range
router.get('/', authMiddleware, async (req, res) => {
  try {
    const { startDate, endDate, patientId } = req.query;
    
    // Determine which userId to use
    let userId = req.user.userId;
    
    // If patientId is provided and user is a companion or doctor, use patientId
    if (patientId && (req.user.role === 'Companion' || req.user.role === 'Doctor')) {
      // You might want to add additional validation here to ensure the companion
      // is actually linked to this patient
      userId = patientId;
    }
    
    const readings = await Reading.find({
      userId: userId,
      timestamp: {
        $gte: new Date(startDate),
        $lte: new Date(endDate),
      },
    }).sort({ timestamp: 1 });
    res.status(200).json(readings);
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
});

// Fetch distinct dates with readings for a user
router.get('/dates', authMiddleware, async (req, res) => {
  try {
    const readings = await Reading.find({ userId: req.user.userId });
    const dates = [...new Set(readings.map(reading => 
      reading.timestamp.toISOString().split('T')[0]
    ))];
    res.status(200).json(dates);
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;