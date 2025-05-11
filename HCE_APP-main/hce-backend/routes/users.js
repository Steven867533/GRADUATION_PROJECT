const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const User = require('../models/user');
const authMiddleware = require('../middleware/auth');


// GET /users/me - Fetch the authenticated user's profile
router.get('/me', authMiddleware, async (req, res) => {
    try {
        const user = await User.findById(req.user.userId).select('-password');
        if (!user) {
            return res.status(404).json({ message: 'User not found' });
        }
        res.json(user);
    } catch (error) {
        console.error('Error fetching user profile:', error);
        res.status(500).json({ message: 'Server error' });
    }
});

// PUT /users/me - Update the authenticated user's profile
router.put('/me', authMiddleware, async (req, res) => {
    try {
        const userId = req.user.userId;
        const user = await User.findById(userId);
        
        if (!user) {
            return res.status(404).json({ message: 'User not found' });
        }

        const updateData = { ...req.body };
        delete updateData.password; // Don't allow password updates through this endpoint
        delete updateData.role; // Don't allow role changes

        // Handle doctor and companion updates by phone number
        if (updateData.doctorPhoneNumber && user.role === 'Patient') {
            const doctor = await User.findOne({ 
                phoneNumber: updateData.doctorPhoneNumber,
                role: 'Doctor'
            });
            
            if (!doctor) {
                return res.status(404).json({ message: 'Doctor not found with the provided phone number' });
            }
            
            updateData.doctorId = doctor._id;
            delete updateData.doctorPhoneNumber;
        }

        if (updateData.companionPhoneNumber && user.role === 'Patient') {
            const companion = await User.findOne({ 
                phoneNumber: updateData.companionPhoneNumber,
                role: 'Companion'
            });
            
            if (!companion) {
                return res.status(404).json({ message: 'Companion not found with the provided phone number' });
            }
            
            updateData.companionId = companion._id;
            delete updateData.companionPhoneNumber;
        }

        if (updateData.patientPhoneNumber && user.role === 'Companion') {
            const patient = await User.findOne({ 
                phoneNumber: updateData.patientPhoneNumber,
                role: 'Patient'
            });
            
            if (!patient) {
                return res.status(404).json({ message: 'Patient not found with the provided phone number' });
            }
            
            updateData.patientId = patient._id;
            delete updateData.patientPhoneNumber;
        }

        const updatedUser = await User.findByIdAndUpdate(
            userId,
            { $set: updateData },
            { new: true, runValidators: true }
        ).select('-password');

        res.json(updatedUser);
    } catch (error) {
        console.error('Error updating user profile:', error);
        if (error.name === 'ValidationError') {
            return res.status(400).json({ message: error.message });
        }
        res.status(500).json({ message: 'Server error' });
    }
});

// GET /users/by-phone - Fetch a user by phone number
router.get('/by-phone', authMiddleware, async (req, res) => {
const { phoneNumber } = req.query;
    if (!phoneNumber) {
    return res.status(400).json({ message: 'Phone number is required' });
    }

    try {
        const user = await User.findOne({ phoneNumber }).select('-password');
        if (!user) {
            return res.status(404).json({ message: 'User not found' });
        }
        res.json(user);
    } catch (error) {
        console.error('Error fetching user by phone:', error);
        res.status(500).json({ message: 'Server error' });
    }
});

// GET /users/search - Search users by phone number (ignores '+' and matches partially)
router.get('/search', authMiddleware, async (req, res) => {
    try {
        const { phoneNumber } = req.query;
        const cleanedNumber = phoneNumber.replace(/\D/g, '');
        if (!cleanedNumber) {
            return res.status(400).json({ message: 'Phone number is required' });
        }
        const regexPattern = new RegExp(cleanedNumber, 'i');
        const users = await User.find({ 
            phoneNumber: regexPattern,
            _id: { $ne: req.user.userId }
        }).select('name phoneNumber');
        res.status(200).json(users);
    } catch (error) {
        console.error('Error searching users:', error);
        res.status(500).json({ message: 'Server error' });
    }
});

// GET /users/:id - Fetch a user by ID
router.get('/:id', authMiddleware, async (req, res) => {
    try {
        const user = await User.findById(req.params.id).select('name phoneNumber');
        if (!user) {
            return res.status(404).json({ message: 'User not found' });
        }
        res.json(user);
    } catch (error) {
        console.error('Error fetching user by ID:', error);
        res.status(500).json({ message: 'Server error' });
    }
});

// PUT /users/:id - Update user information
router.put('/:id', authMiddleware, async (req, res) => {
    try {
        // Check if the user is updating their own profile
        if (req.user.userId !== req.params.id) {
            return res.status(403).json({ message: 'Not authorized to update this user' });
        }

        const user = await User.findById(req.params.id);
        if (!user) {
            return res.status(404).json({ message: 'User not found' });
        }

        const updateData = { ...req.body };
        delete updateData.password; // Don't allow password updates through this endpoint
        delete updateData.role; // Don't allow role changes

        // Handle doctor and companion updates by phone number
        if (updateData.doctorPhoneNumber && user.role === 'Patient') {
            const doctor = await User.findOne({ 
                phoneNumber: updateData.doctorPhoneNumber,
                role: 'Doctor'
            });
            
            if (!doctor) {
                return res.status(404).json({ message: 'Doctor not found with the provided phone number' });
            }
            
            updateData.doctorId = doctor._id;
            delete updateData.doctorPhoneNumber;
        }

        if (updateData.companionPhoneNumber && user.role === 'Patient') {
            const companion = await User.findOne({ 
                phoneNumber: updateData.companionPhoneNumber,
                role: 'Companion'
            });
            
            if (!companion) {
                return res.status(404).json({ message: 'Companion not found with the provided phone number' });
            }
            
            updateData.companionId = companion._id;
            delete updateData.companionPhoneNumber;
        }

        if (updateData.patientPhoneNumber && user.role === 'Companion') {
            const patient = await User.findOne({ 
                phoneNumber: updateData.patientPhoneNumber,
                role: 'Patient'
            });
            
            if (!patient) {
                return res.status(404).json({ message: 'Patient not found with the provided phone number' });
            }
            
            updateData.patientId = patient._id;
            delete updateData.patientPhoneNumber;
        }

        const updatedUser = await User.findByIdAndUpdate(
            req.params.id,
            { $set: updateData },
            { new: true, runValidators: true }
        ).select('-password');

        res.json(updatedUser);
    } catch (error) {
        console.error('Error updating user:', error);
        if (error.name === 'ValidationError') {
            return res.status(400).json({ message: error.message });
        }
        res.status(500).json({ message: 'Server error' });
    }
});

module.exports = router;