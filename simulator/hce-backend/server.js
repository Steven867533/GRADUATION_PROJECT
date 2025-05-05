require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');

const app = express();

// Validate environment variables
if (!process.env.MONGODB_URI) {
  console.error('Error: MONGODB_URI is not defined in .env');
  process.exit(1);
}
if (!process.env.JWT_SECRET) {
  console.error('Error: JWT_SECRET is not defined in .env');
  process.exit(1);
}

const debugMiddleware = (req, res, next) => {
  const timestamp = new Date().toISOString();

  console.log(`[${timestamp}] Request: ${req.method} ${req.url}`);
  console.log(`[${timestamp}] Headers: ${JSON.stringify(req.headers, null, 2)}`); // Pretty print the headers
  if (req.body && Object.keys(req.body).length > 0) {
    console.log(`[${timestamp}] Request Payload: ${JSON.stringify(req.body)}`);
  } else {
    console.log(`[${timestamp}] Request Payload: None`);
  }

  const originalSend = res.send;

  res.send = function (body) {
    console.log(`[${timestamp}] Response Status: ${res.statusCode}`);
    console.log(`[${timestamp}] Response Body: ${typeof body === 'string' ? body : JSON.stringify(body)}`);

    return originalSend.call(this, body);
  };

  next();
};


app.use(cors({
  origin: '*',
}));

app.use(express.json());
app.use(debugMiddleware);

// Add test route
app.get('/', (req, res) => {
  res.json({
    message: 'Server is running',
    timestamp: new Date().toISOString(),
    status: 'healthy',
    version: process.env.npm_package_version || '1.0.0'
  });
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'UP',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    mongodb: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected'
  });
});

// MongoDB connection with reconnection logic
mongoose.connect(process.env.MONGODB_URI, {
  serverSelectionTimeoutMS: 5000,
})
  .then(() => console.log('Connected to MongoDB'))
  .catch((err) => console.error('MongoDB connection error:', err));

// Handle MongoDB connection events
mongoose.connection.on('disconnected', () => {
  console.warn('MongoDB disconnected. Attempting to reconnect...');
});
mongoose.connection.on('reconnected', () => {
  console.log('MongoDB reconnected');
});
mongoose.connection.on('error', (err) => {
  console.error('MongoDB error:', err);
});

// Mount routes
app.use('/auth', require('./routes/auth'));
app.use('/users', require('./routes/users'));
app.use('/locations', require('./routes/locations'));
app.use('/messages', require('./routes/messages'));
app.use('/readings', require('./routes/readings'));

// Global error-handling middleware
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
      message: 'Internal server error',
      error: process.env.NODE_ENV === 'development' ? err.message : undefined,
  });
});

const PORT = process.env.PORT || 5000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});

process.on('SIGINT', async() => {
  console.log('Shutting down server...');
  await mongoose.connection.close();
  console.log('MongoDB connection closed');
  process.exit(0);
});