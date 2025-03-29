const mongoose = require('mongoose');

const transactionSchema = new mongoose.Schema({
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: [true, 'User ID is required']
  },
  type: {
    type: String,
    enum: ['topUp', 'gameTransaction'],
    required: [true, 'Transaction type is required']
  },
  amount: {
    type: Number,
    required: [true, 'Transaction amount is required']
  },
  description: {
    type: String,
    required: [true, 'Transaction description is required']
  },
  gameId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Game',
    default: null
  },
  timestamp: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true
});

// Index for efficient querying
transactionSchema.index({ userId: 1, timestamp: -1 });

// Virtual property to get rupiah amount
transactionSchema.virtual('rupiahAmount').get(function() {
  return this.amount * 500; // 1 chip = 500 rupiah
});

// Method to create a top-up transaction
transactionSchema.statics.createTopUp = async function(userId, chipAmount) {
  return this.create({
    userId,
    type: 'topUp',
    amount: chipAmount,
    description: 'Top-up',
  });
};

// Method to create a game transaction
transactionSchema.statics.createGameTransaction = async function(
  userId,
  chipAmount,
  gameId,
  description = 'Game transaction'
) {
  return this.create({
    userId,
    type: 'gameTransaction',
    amount: chipAmount,
    description: description,
    gameId: gameId
  });
};

// Method to get user's transaction history
transactionSchema.statics.getUserTransactions = async function(userId, limit = 10, page = 1) {
  const skip = (page - 1) * limit;

  return this.find({ userId })
    .sort({ timestamp: -1 })
    .skip(skip)
    .limit(limit)
    .populate('gameId', 'name')
    .exec();
};

const Transaction = mongoose.model('Transaction', transactionSchema);

module.exports = Transaction;