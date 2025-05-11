const express = require('express');
const router = express.Router();
const Message = require('../models/message');
const authMiddleware = require('../middleware/auth');
const mongoose = require('mongoose');

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
    
    // Convert userId to ObjectId for correct comparison
    const userObjectId = new mongoose.Types.ObjectId(userId);
    
    const unseenCount = await Message.countDocuments({
      recipientId: userObjectId,
      seenTime: null,
    });
    
    console.log(`Unseen message count for user ${userId}: ${unseenCount}`);
    res.status(200).json({ unseenCount });
  } catch (error) {
    console.error('Error fetching unseen message count:', error);
    res.status(500).json({ message: 'Server error' });
  }
});

// Get users who have sent unseen messages with counts
router.get('/unseen-persons', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;
    
    // Convert userId to ObjectId for correct comparison
    const userObjectId = new mongoose.Types.ObjectId(userId);
    
    console.log(`Fetching unseen persons for user ID: ${userId} (ObjectId: ${userObjectId})`);
    
    // Aggregate to get unseen messages grouped by sender
    const unseenMessages = await Message.aggregate([
      // Match only unseen messages where current user is the recipient
      {
        $match: {
          recipientId: userObjectId, // Use ObjectId instead of string
          seenTime: null
        }
      },
      // Group by sender and count messages
      {
        $group: {
          _id: "$senderId",
          unseenCount: { $sum: 1 },
          latestMessage: { $last: "$content" },
          latestMessageTime: { $max: "$sentTime" }
        }
      },
      // Sort by latest message time (most recent first)
      {
        $sort: { latestMessageTime: -1 }
      },
      // Lookup sender details
      {
        $lookup: {
          from: "users", // Collection name (might need adjustment based on your model setup)
          localField: "_id",
          foreignField: "_id",
          as: "sender"
        }
      },
      // Unwind the sender array
      {
        $unwind: {
          path: "$sender",
          preserveNullAndEmptyArrays: false // Skip documents where sender wasn't found
        }
      },
      // Project only the needed fields
      {
        $project: {
          _id: 1,
          unseenCount: 1,
          latestMessage: 1,
          latestMessageTime: 1,
          "sender.name": 1,
          "sender.phoneNumber": 1,
          "sender.role": 1
        }
      }
    ]);
    
    // Add additional debug logging
    console.log(`Raw unseen messages result: ${JSON.stringify(unseenMessages)}`);
    
    // Format the response
    const formattedResponse = unseenMessages.map(item => ({
      _id: item._id,
      name: item.sender.name,
      phoneNumber: item.sender.phoneNumber,
      role: item.sender.role,
      unseenCount: item.unseenCount,
      latestMessage: item.latestMessage,
      latestMessageTime: item.latestMessageTime
    }));
    
    console.log(`Found ${formattedResponse.length} users with unseen messages for user ${userId}`);
    
    res.status(200).json(formattedResponse);
  } catch (error) {
    console.error('Error fetching unseen message senders:', error);
    res.status(500).json({ message: 'Server error' });
  }
});

// Get messages between current user and a specific recipient
router.get('/:recipientId', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;
    const { recipientId } = req.params;
    
    // Convert IDs to ObjectId
    const userObjectId = new mongoose.Types.ObjectId(userId);
    const recipientObjectId = new mongoose.Types.ObjectId(recipientId);
    
    // Find messages where either:
    // 1. Current user is sender and recipient is the specified user
    // 2. Current user is recipient and sender is the specified user
    const messages = await Message.find({
      $or: [
        { senderId: userObjectId, recipientId: recipientObjectId },
        { senderId: recipientObjectId, recipientId: userObjectId }
      ]
    })
    .sort({ sentTime: 1 }) // Sort by sent time ascending
    .populate('senderId', 'name') // Populate sender details
    .populate('recipientId', 'name'); // Populate recipient details
    
    // Update receivedTime for messages sent to the current user
    await Message.updateMany(
      { 
        senderId: recipientObjectId, 
        recipientId: userObjectId,
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
    
    // Convert userId to ObjectId
    const userObjectId = new mongoose.Types.ObjectId(userId);
    
    // Find the message and ensure the current user is the recipient
    const message = await Message.findOne({
      _id: messageId,
      recipientId: userObjectId,
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

// NEW: Mark all messages from a sender as seen
router.put('/mark-all-seen/:senderId', authMiddleware, async (req, res) => {
  try {
    const { senderId } = req.params;
    const userId = req.user.userId;
    
    // Convert IDs to ObjectId
    const userObjectId = new mongoose.Types.ObjectId(userId);
    const senderObjectId = new mongoose.Types.ObjectId(senderId);
    
    // Update all unseen messages from this sender to the current user
    const result = await Message.updateMany(
      { 
        senderId: senderObjectId,
        recipientId: userObjectId,
        seenTime: null 
      },
      { 
        $set: { seenTime: new Date() } 
      }
    );
    
    res.status(200).json({ 
      message: 'Messages marked as seen',
      count: result.modifiedCount
    });
  } catch (error) {
    console.error('Error marking messages as seen:', error);
    res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;