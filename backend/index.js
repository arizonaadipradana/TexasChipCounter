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

  // Store user info when available
  let currentUser = null;

  // Authenticate socket connection with token (optional enhancement)
  socket.on('authenticate', (data) => {
    try {
      const token = data.token;
      if (token) {
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        currentUser = {
          userId: decoded.id
        };
        console.log(`Socket ${socket.id} authenticated as user ${currentUser.userId}`);
      }
    } catch (error) {
      console.error('Socket authentication error:', error);
    }
  });

  // Handle joining a game room
  socket.on('join_game', (gameId) => {
    socket.join(gameId);
    console.log(`Socket ${socket.id} joined game: ${gameId}`);

    // Emit an event to all sockets in the room that a new socket joined
    // This is just to notify, not to update the game state
    socket.to(gameId).emit('socket_joined', {
      socketId: socket.id,
      timestamp: new Date()
    });
  });

  // Handle leaving a game room
  socket.on('leave_game', (gameId) => {
    socket.leave(gameId);
    console.log(`Socket ${socket.id} left game: ${gameId}`);

    // Emit an event to all sockets in the room that a socket left
    socket.to(gameId).emit('socket_left', {
      socketId: socket.id,
      timestamp: new Date()
    });
  });

  // Handle game actions
  socket.on('game_action', (data) => {
    console.log(`Game action in ${data.gameId}:`, data.action);

    // Enhanced logging
    if (data.action === 'player_joined') {
      console.log(`Player joined game ${data.gameId}`);
      // Add the player's username to the event if available
      if (data.game && data.game.players) {
        const newPlayer = data.game.players[data.game.players.length - 1];
        data.playerName = newPlayer.username;
      }
    } else if (data.action === 'player_left') {
      console.log(`Player left game ${data.gameId}`);
    }

    // Broadcast the action to all players in the game room
    // Including the original sender to ensure they have the latest state
    io.to(data.gameId).emit(data.action, data);

    // Also emit a generic game_update event for any listeners
    io.to(data.gameId).emit('game_update', data);
  });

  // Handle disconnection
  socket.on('disconnect', () => {
    console.log('Client disconnected:', socket.id);
    // Additional cleanup can be done here if needed
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