const express = require('express');
const userController = require('../controllers/user.controller');
const verifyToken = require('../middleware/auth.middleware');

const router = express.Router();

// Public routes
router.post('/register', userController.register);
router.post('/login', userController.login);

// Protected routes (require authentication)
router.get('/me', verifyToken, userController.getCurrentUser);
router.post('/topup', verifyToken, userController.topUp);
router.get('/transactions', verifyToken, userController.getTransactionHistory);

router.post('/refresh-token', userController.refreshToken);

module.exports = router;
