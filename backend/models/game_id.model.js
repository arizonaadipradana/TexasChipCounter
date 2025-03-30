const mongoose = require('mongoose');

// Very basic schema for game IDs
const gameIdSchema = new mongoose.Schema({
  shortId: {
    type: String,
    required: true,
    unique: true,
    uppercase: true,
    trim: true
  },
  fullId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Game',
    required: true
  }
}, {
  timestamps: true
});

// Create the model, checking if it already exists first
const GameId = mongoose.models.GameId || mongoose.model('GameId', gameIdSchema);

module.exports = GameId;