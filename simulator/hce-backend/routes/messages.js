const express = require('express');
const router = express.Router();
const Message = require('../models/message');
const authMiddleware = require('../middleware/auth');

// Send a message
router.post('/', authMiddleware, async (req, res) => {
  const { recipientId, content } = req.body;
  if (!recipientId || !content) {
    return res.status(400).json({ message: 'Recipient ID and content are required' });
  }

  try {
    const message = new Message({
      senderId: req.user.userId,
      recipientId,
      content,
    });
    await message.save();
    res.status(201).json({ message: 'Message sent' });
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

// IMPORTANT: Place specific routes BEFORE parameter routes
// Get unseen message count
router.get('/unseen-count', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;
    const unseenCount = await Message.countDocuments({
      recipientId: userId,
      seenTime: null,
    });
    res.status(200).json({ unseenCount });
  } catch (error) {
    console.error('Error fetching unseen message count:', error);
    res.status(500).json({ message: 'Server error' });
  }
});

// Get messages between current user and a specific recipient
router.get('/:recipientId', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;
    const { recipientId } = req.params;
    
    // Find messages where either:
    // 1. Current user is sender and recipient is the specified user
    // 2. Current user is recipient and sender is the specified user
    const messages = await Message.find({
      $or: [
        { senderId: userId, recipientId: recipientId },
        { senderId: recipientId, recipientId: userId }
      ]
    })
    .sort({ sentTime: 1 }) // Sort by sent time ascending
    .populate('senderId', 'name') // Populate sender details
    .populate('recipientId', 'name'); // Populate recipient details
    
    // Update receivedTime for messages sent to the current user
    await Message.updateMany(
      { 
        senderId: recipientId, 
        recipientId: userId,
        receivedTime: null 
      },
      { 
        $set: { receivedTime: new Date() } 
      }
    );
    
    res.status(200).json(messages);
  } catch (error) {
    console.error('Error fetching messages:', error);
    res.status(500).json({ message: 'Server error' });
  }
});

// Mark a message as seen
router.put('/:messageId/seen', authMiddleware, async (req, res) => {
  try {
    const { messageId } = req.params;
    const userId = req.user.userId;
    
    // Find the message and ensure the current user is the recipient
    const message = await Message.findOne({
      _id: messageId,
      recipientId: userId,
      seenTime: null // Only update if not already seen
    });
    
    if (!message) {
      return res.status(404).json({ 
        message: 'Message not found or you are not authorized to mark it as seen' 
      });
    }
    
    // Update the seenTime
    message.seenTime = new Date();
    await message.save();
    
    res.status(200).json({ message: 'Message marked as seen' });
  } catch (error) {
    console.error('Error marking message as seen:', error);
    res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;