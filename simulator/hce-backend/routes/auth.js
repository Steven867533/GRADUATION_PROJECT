const express = require('express');
const router = express.Router();
const {
    body,
    validationResult
} = require('express-validator');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const User = require('../models/user');

// Signup endpoint
router.post(
    '/signup', [
        body('name').notEmpty().withMessage('Name is required'),
        body('email').isEmail().withMessage('Valid email is required'),
        body('password').isLength({
            min: 8
        }).withMessage('Password must be at least 8 characters'),
        body('phoneNumber').notEmpty().withMessage('Phone number is required'),
        body('birthdate').isISO8601().withMessage('Valid birthdate is required'),
        body('role').isIn(['Doctor', 'Patient', 'Companion']).withMessage('Invalid role'),
        body('bloodPressureType')
        .if(body('role').equals('Patient'))
        .isIn(['Low', 'Average', 'High'])
        .withMessage('Invalid blood pressure type'),
        // Replace MongoDB ID validation with phone number validation
        body('doctorPhoneNumber')
        .if(body('role').equals('Patient'))
        .optional()
        .notEmpty()
        .withMessage('Doctor phone number is required for patients'),
        body('patientPhoneNumber')
        .if(body('role').equals('Companion'))
        .optional()
        .notEmpty()
        .withMessage('Patient phone number is required for companions'),
    ],
    async(req, res) => {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({
                errors: errors.array()
            });
        }

        const {
            name,
            email,
            password,
            phoneNumber,
            birthdate,
            role,
            bloodPressureType,
            doctorPhoneNumber,
            patientPhoneNumber
        } = req.body;

        try {
            let user = await User.findOne({
                email
            });
            if (user) {
                return res.status(400).json({
                    message: 'User already exists'
                });
            }

            // Find doctor by phone number if provided
            let doctorId;
            if (role === 'Patient' && doctorPhoneNumber) {
                const doctor = await User.findOne({
                    phoneNumber: doctorPhoneNumber,
                    role: 'Doctor'
                });
                if (doctor) {
                    doctorId = doctor._id;
                }
            }

            // Find patient by phone number if provided
            let patientId;
            if (role === 'Companion' && patientPhoneNumber) {
                const patient = await User.findOne({
                    phoneNumber: patientPhoneNumber,
                    role: 'Patient'
                });
                if (patient) {
                    patientId = patient._id;
                }
            }

            user = new User({
                name,
                email,
                password: await bcrypt.hash(password, 10),
                phoneNumber,
                birthdate,
                role,
                bloodPressureType: role === 'Patient' ? bloodPressureType : undefined,
                doctorId: doctorId,
                patientId: patientId,
            });

            await user.save();

            const token = jwt.sign({
                    userId: user._id,
                    role: user.role
                },
                process.env.JWT_SECRET, {
                    expiresIn: '1h'
                }
            );

            res.status(201).json({
                token,
                userId: user._id.toString()
            });
        } catch (err) {
            console.error('Signup error:', err);
            res.status(500).json({
                message: 'Server error'
            });
        }
    }
);

// Login endpoint
router.post(
    '/login', [
        body('email').isEmail().withMessage('Valid email is required'),
        body('password').notEmpty().withMessage('Password is required'),
    ],
    async(req, res) => {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({
                errors: errors.array()
            });
        }

        const {
            email,
            password
        } = req.body;

        try {
            const user = await User.findOne({
                email
            });
            if (!user) {
                return res.status(400).json({
                    message: 'Invalid credentials'
                });
            }

            const isMatch = await bcrypt.compare(password, user.password);
            if (!isMatch) {
                return res.status(400).json({
                    message: 'Invalid credentials'
                });
            }

            const token = jwt.sign({
                    userId: user._id,
                    role: user.role
                },
                process.env.JWT_SECRET, {
                    expiresIn: '1h'
                }
            );

            res.json({
                token
            });
        } catch (err) {
            console.error('Login error:', err);
            res.status(500).json({
                message: 'Server error'
            });
        }
    }
);

module.exports = router;