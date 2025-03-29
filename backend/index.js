// Load environment variables first, before any other imports
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '.env') });

console.log('Environment variables loaded:');
console.log('MONGODB_URI:', process.env.MONGODB_URI);
console.log('PORT:', process.env.PORT);
console.log('NODE_ENV:', process.env.NODE_ENV);

const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const morgan = require('morgan');
const http = require('http');
const socketIo = require('socket.io');

// Import routes
const userRoutes = require('./routes/user.routes');
const gameRoutes = require('./routes/game.routes');
const transactionRoutes = require('./routes/transaction.routes');

// Create Express app
const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST']
  }
});

// Middleware
app.use(cors());
app.use(express.json());

// Logging middleware
if (process.env.ENABLE_LOGGING === 'true') {
  app.use(morgan('dev'));
}

// Database connection
if (!process.env.MONGODB_URI) {
  console.error('MONGODB_URI is not defined in environment variables');
  console.error('Setting a default MongoDB URI for local development');
  process.env.MONGODB_URI = 'mongodb://localhost:27017/poker_chip_counter';
}

mongoose.connect(process.env.MONGODB_URI, {
  useNewUrlParser: true,
  useUnifiedTopology: true
})
  .then(() => {
    console.log('Connected to MongoDB');
  })
  .catch((error) => {
    console.error('MongoDB connection error:', error);
    process.exit(1);
  });

// Routes
app.use('/api/users', userRoutes);
app.use('/api/games', gameRoutes);
app.use('/api/transactions', transactionRoutes);

// Socket.io connection handler
io.on('connection', (socket) => {
  console.log('New client connected:', socket.id);

  // Handle joining a game room
  socket.on('join_game', (gameId) => {
    socket.join(gameId);
    console.log(`Socket ${socket.id} joined game: ${gameId}`);
  });

  // Handle leaving a game room
  socket.on('leave_game', (gameId) => {
    socket.leave(gameId);
    console.log(`Socket ${socket.id} left game: ${gameId}`);
  });

  // Handle game actions
  socket.on('game_action', (data) => {
    // Broadcast the action to all players in the game room
    io.to(data.gameId).emit('game_update', data);
    console.log(`Game action in ${data.gameId}:`, data.action);
  });

  // Handle disconnection
  socket.on('disconnect', () => {
    console.log('Client disconnected:', socket.id);
  });
});

// Default route
app.get('/', (req, res) => {
  res.send('Poker Chip Counter API is running');
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({
    success: false,
    message: 'Internal server error',
    error: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

// Start server
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});