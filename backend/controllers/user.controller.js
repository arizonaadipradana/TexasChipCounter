const jwt = require('jsonwebtoken');
const User = require('../models/user.model');
const Transaction = require('../models/transaction.model');

// Register a new user
exports.register = async (req, res) => {
  try {
    console.log("Register request received:", req.body);
    const { username, email, password } = req.body;

    // Check if user already exists
    const existingUser = await User.findOne({
      $or: [{ email }, { username }]
    });

    if (existingUser) {
      return res.status(400).json({
        success: false,
        message: 'User with this email or username already exists'
      });
    }

    // Create new user
    const user = new User({
      username,
      email,
      password,
      chipBalance: 0 // Start with 0 chips
    });

    // Save user to database
    await user.save();

    // Generate JWT token
    const token = jwt.sign(
      { id: user._id },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRATION }
    );

    // Return user data and token
    return res.status(201).json({
      success: true,
      message: 'User registered successfully',
      user: {
        _id: user._id,
        username: user.username,
        email: user.email,
        chipBalance: user.chipBalance
      },
      token
    });
  } catch (error) {
    console.error('Register error details:', error);
    return res.status(500).json({
      success: false,
      message: 'Registration failed',
      error: error.message
    });
  }
};

// Login user
exports.login = async (req, res) => {
  try {
    const { email, password } = req.body;

    // Find user by email
    const user = await User.findOne({ email });

    if (!user) {
      return res.status(401).json({
        success: false,
        message: 'Invalid email or password'
      });
    }

    // Check if password is correct
    const isPasswordValid = await user.comparePassword(password);

    if (!isPasswordValid) {
      return res.status(401).json({
        success: false,
        message: 'Invalid email or password'
      });
    }

    // Update last login
    user.lastLogin = Date.now();
    await user.save();

    // Generate JWT token
    const token = jwt.sign(
      { id: user._id },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRATION }
    );

    // Return user data and token
    return res.status(200).json({
      success: true,
      message: 'Login successful',
      user: {
        _id: user._id,
        username: user.username,
        email: user.email,
        chipBalance: user.chipBalance
      },
      token
    });
  } catch (error) {
    console.error('Login error:', error);
    return res.status(500).json({
      success: false,
      message: 'Login failed',
      error: error.message
    });
  }
};

// Get current user data
exports.getCurrentUser = async (req, res) => {
  try {
    // Find user (req.userId is set by auth middleware)
    const user = await User.findById(req.userId).select('-password');

    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    return res.status(200).json({
      success: true,
      user: {
        _id: user._id,
        username: user.username,
        email: user.email,
        chipBalance: user.chipBalance,
        createdAt: user.createdAt,
        lastLogin: user.lastLogin
      }
    });
  } catch (error) {
    console.error('Get current user error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to get user data',
      error: error.message
    });
  }
};

// Top up user's chip balance
// Top up user's chip balance
exports.topUp = async (req, res) => {
  try {
    const { amount } = req.body;
    const chipAmount = parseInt(amount);
    const userId = req.userId;

    // Validate amount
    if (!chipAmount || chipAmount <= 0) {
      return res.status(400).json({
        success: false,
        message: 'Invalid chip amount'
      });
    }

    // Find user
    const user = await User.findById(userId);

    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    // Update chip balance
    user.chipBalance += chipAmount;
    await user.save();

    // Create transaction record with improved description
    await Transaction.createTopUp(
      user._id,
      chipAmount, 
      `Top-up - @${user.username}`
    );

    return res.status(200).json({
      success: true,
      message: `Successfully added ${chipAmount} chips`,
      chipBalance: user.chipBalance
    });
  } catch (error) {
    console.error('Top up error:', error);
    return res.status(500).json({
      success: false,
      message: 'Top up failed',
      error: error.message
    });
  }
};

// Get user's transaction history
exports.getTransactionHistory = async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 10;
    const page = parseInt(req.query.page) || 1;

    // Get user transactions
    const transactions = await Transaction.getUserTransactions(
      req.userId,
      limit,
      page
    );

    return res.status(200).json({
      success: true,
      transactions
    });
  } catch (error) {
    console.error('Get transaction history error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to get transaction history',
      error: error.message
    });
  }
};

exports.refreshToken = async (req, res) => {
  try {
    const { refreshToken } = req.body;

    // Validate refresh token
    // If valid, issue new access token

    // Generate new JWT token
    const token = jwt.sign(
      { id: user._id },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRATION }
    );

    return res.status(200).json({
      success: true,
      message: 'Token refreshed successfully',
      token
    });
  } catch (error) {
    console.error('Refresh token error:', error);
    return res.status(401).json({
      success: false,
      message: 'Failed to refresh token',
      error: error.message
    });
  }
};