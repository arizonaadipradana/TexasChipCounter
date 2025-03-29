const Transaction = require('../models/transaction.model');
const User = require('../models/user.model');

// Create a new transaction (manual top-up for admin use)
exports.createTransaction = async (req, res) => {
  try {
    const { userId, type, amount, description, gameId } = req.body;
    const adminId = req.userId;

    // Check if request is from an admin (would need admin middleware in a real app)
    if (!adminId) {
      return res.status(403).json({
        success: false,
        message: 'Unauthorized: Admin access required'
      });
    }

    // Validate transaction data
    if (!userId || !type || !amount) {
      return res.status(400).json({
        success: false,
        message: 'UserId, type, and amount are required'
      });
    }

    // Get user info to include in description
    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    // Create transaction with improved description
    const transaction = new Transaction({
      userId,
      type,
      amount: parseInt(amount),
      description: description || `${type === 'topUp' ? 'Top-up' : type} - @${user.username}`,
      gameId: gameId || null
    });

    // Save transaction
    await transaction.save();

    // Update user chip balance if it's a top-up
    if (type === 'topUp') {
      user.chipBalance += parseInt(amount);
      await user.save();
    }

    return res.status(201).json({
      success: true,
      message: 'Transaction created successfully',
      transaction
    });
  } catch (error) {
    console.error('Create transaction error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to create transaction',
      error: error.message
    });
  }
};

// Get transaction history for a user
exports.getUserTransactions = async (req, res) => {
  try {
    const { userId } = req.params;
    const requesterId = req.userId;

    // Ensure the requester is accessing their own data or is an admin
    if (userId !== requesterId) {
      return res.status(403).json({
        success: false,
        message: 'Unauthorized: You can only access your own transaction history'
      });
    }

    const limit = parseInt(req.query.limit) || 10;
    const page = parseInt(req.query.page) || 1;

    // Get transactions
    const transactions = await Transaction.getUserTransactions(userId, limit, page);

    // Get total count for pagination
    const totalCount = await Transaction.countDocuments({ userId });

    return res.status(200).json({
      success: true,
      transactions,
      pagination: {
        page,
        limit,
        totalCount,
        totalPages: Math.ceil(totalCount / limit)
      }
    });
  } catch (error) {
    console.error('Get user transactions error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to get transaction history',
      error: error.message
    });
  }
};

// Get transaction details
exports.getTransaction = async (req, res) => {
  try {
    const { transactionId } = req.params;
    const userId = req.userId;

    // Find transaction
    const transaction = await Transaction.findById(transactionId);

    if (!transaction) {
      return res.status(404).json({
        success: false,
        message: 'Transaction not found'
      });
    }

    // Ensure user is accessing their own transaction
    if (transaction.userId.toString() !== userId.toString()) {
      return res.status(403).json({
        success: false,
        message: 'Unauthorized: You can only access your own transactions'
      });
    }

    return res.status(200).json({
      success: true,
      transaction
    });
  } catch (error) {
    console.error('Get transaction error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to get transaction details',
      error: error.message
    });
  }
};

// Get game transactions
exports.getGameTransactions = async (req, res) => {
  try {
    const { gameId } = req.params;
    const userId = req.userId;

    // Find transactions for this game
    const transactions = await Transaction.find({
      gameId,
      type: 'gameTransaction'
    }).sort({ timestamp: -1 });

    // Filter transactions to show only user's own and relevant game summary data
    const filteredTransactions = transactions.filter(
      transaction => transaction.userId.toString() === userId.toString()
    );

    return res.status(200).json({
      success: true,
      transactions: filteredTransactions,
      gameSummary: {
        totalTransactions: transactions.length,
        userTransactions: filteredTransactions.length
      }
    });
  } catch (error) {
    console.error('Get game transactions error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to get game transactions',
      error: error.message
    });
  }
};