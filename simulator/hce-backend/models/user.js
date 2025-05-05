const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
  name: {
    type: String,
    required: true,
  },
  email: {
    type: String,
    required: true,
    unique: true,
  },
  password: {
    type: String,
    required: true,
  },
  phoneNumber: {
    type: String,
    required: true,
    unique: true, // This creates an index automatically
  },
  birthdate: {
    type: Date,
    required: true,
  },
  role: {
    type: String,
    enum: ['Patient', 'Companion', 'Doctor'],
    required: true,
  },
  patientId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: false
  },
  doctorId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: false
  },
  companionId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: false
  },
  bloodPressureType: {
    type: String,
    enum: ['High', 'Average', 'Low', 'N/A'],
    default: 'N/A',
    required: function() {
      return this.role === 'Patient';
    },
  },
  createdAt: {
    type: Date,
    default: Date.now,
  },
});

// Add a pre-save validation that skips the first save
userSchema.pre('validate', function(next) {
  // Skip validation for new documents (during creation)
  if (this.isNew) {
    return next();
  }
  
  // For existing documents, enforce the relationship requirements
  if (this.role === 'Companion' && !this.patientId) {
    this.invalidate('patientId', 'Path `patientId` is required for companions.');
  }
  
  if (this.role === 'Patient' && (!this.doctorId || !this.companionId)) {
    if (!this.doctorId) {
      this.invalidate('doctorId', 'Path `doctorId` is required for patients.');
    }
    if (!this.companionId) {
      this.invalidate('companionId', 'Path `companionId` is required for patients.');
    }
  }
  
  next();
});

module.exports = mongoose.model('User', userSchema);