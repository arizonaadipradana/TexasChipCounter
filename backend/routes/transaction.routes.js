const express = require('express');
const transactionController = require('../controllers/transaction.controller');
const verifyToken = require('../middleware/auth.middleware');

const router = express.Router();

// All transaction routes require authentication
router.use(verifyToken);

// Create a new transaction (admin route)
router.post('/', transactionController.createTransaction);

// Get user's transaction history
router.get('/user/:userId', transactionController.getUserTransactions);

// Get transaction details
router.get('/:transactionId', transactionController.getTransaction);

// Get game transactions
router.get('/game/:gameId', transactionController.getGameTransactions);

module.exports = router;