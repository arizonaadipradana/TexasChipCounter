const mongoose = require('mongoose');

const playerSchema = new mongoose.Schema({
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  username: {
    type: String,
    required: true
  },
  chipBalance: {
    type: Number,
    required: true,
    min: 0
  },
  isActive: {
    type: Boolean,
    default: true
  },
  position: {
    type: Number,
    required: false
  }
}, { _id: false });

const gameSchema = new mongoose.Schema({
  name: {
    type: String,
    required: [true, 'Game name is required'],
    trim: true
  },
  hostId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: [true, 'Host ID is required']
  },
  players: {
    type: [playerSchema],
    default: []
  },
  smallBlind: {
    type: Number,
    required: [true, 'Small blind amount is required'],
    min: 1
  },
  bigBlind: {
    type: Number,
    required: [true, 'Big blind amount is required'],
    min: 2
  },
  status: {
    type: String,
    enum: ['pending', 'active', 'completed'],
    default: 'pending'
  },
  currentPlayerIndex: {
    type: Number,
    default: 0
  },
  pot: {
    type: Number,
    default: 0
  },
  currentBet: {
    type: Number,
    default: 0
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  updatedAt: {
    type: Date,
    default: Date.now
  },
  endedAt: {
    type: Date,
    default: null
  }
}, {
  timestamps: true
});

// Method to add a player to the game
gameSchema.methods.addPlayer = function(player) {
  // Check if player already exists
  const existingPlayerIndex = this.players.findIndex(
    p => p.userId.toString() === player.userId.toString()
  );

  if (existingPlayerIndex === -1) {
    this.players.push(player);
  } else {
    // Update existing player data
    this.players[existingPlayerIndex] = {
      ...this.players[existingPlayerIndex],
      ...player,
      isActive: true
    };
  }

  return this;
};

// Method to remove a player from the game
gameSchema.methods.removePlayer = function(userId) {
  this.players = this.players.filter(player => player.userId.toString() !== userId.toString());
  return this;
};

// Method to update a player's chip balance
gameSchema.methods.updatePlayerChips = function(userId, chipAmount) {
  const playerIndex = this.players.findIndex(
    player => player.userId.toString() === userId.toString()
  );

  if (playerIndex !== -1) {
    this.players[playerIndex].chipBalance += chipAmount;
    // Ensure balance doesn't go below zero
    if (this.players[playerIndex].chipBalance < 0) {
      this.players[playerIndex].chipBalance = 0;
    }
    return true;
  }
  return false;
};

// Method to get active players
gameSchema.methods.getActivePlayers = function() {
  return this.players.filter(player => player.isActive);
};

// Method to start the game
gameSchema.methods.startGame = function() {
  this.status = 'active';
  this.updatedAt = Date.now();
  return this;
};

// Method to end the game
gameSchema.methods.endGame = function() {
  this.status = 'completed';
  this.endedAt = Date.now();
  this.updatedAt = Date.now();
  return this;
};

// Move to the next player
gameSchema.methods.nextTurn = function() {
  const activePlayers = this.getActivePlayers();
  if (activePlayers.length <= 1) {
    return false; // Game should end if only one active player remains
  }

  // Find next active player
  let nextIndex = this.currentPlayerIndex;
  do {
    nextIndex = (nextIndex + 1) % this.players.length;
  } while (!this.players[nextIndex].isActive);

  this.currentPlayerIndex = nextIndex;
  this.updatedAt = Date.now();
  return true;
};

const Game = mongoose.model('Game', gameSchema);

module.exports = Game;