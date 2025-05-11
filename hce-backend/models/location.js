const mongoose = require('mongoose');

const locationSchema = new mongoose.Schema({
name: { type: String, required: true },
type: { type: String, required: true, enum: ['Pharmacy', 'Doctor'] },
coordinates: {
latitude: { type: Number, required: true },
longitude: { type: Number, required: true },
},
address: { type: String },
});

module.exports = mongoose.model('Location', locationSchema);