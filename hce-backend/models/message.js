const mongoose = require('mongoose');

const messageSchema = new mongoose.Schema({
    senderId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
    },
    recipientId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
    },
    content: {
        type: String,
        required: true,
    },
    sentTime: {
        type: Date,
        default: Date.now,
    },
    receivedTime: {
        type: Date,
    },
    seenTime: {
        type: Date,
    },
});

module.exports = mongoose.model('Message', messageSchema);