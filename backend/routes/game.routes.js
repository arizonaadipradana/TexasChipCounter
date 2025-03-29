const express = require('express');
const gameController = require('../controllers/game.controller');
const verifyToken = require('../middleware/auth.middleware');

const router = express.Router();

// All game routes require authentication
router.use(verifyToken);

// Get all games (new route that handles status=all query parameter)
router.get('/', gameController.getAllGames);

// Create a new game
router.post('/', gameController.createGame);

// Get active games
router.get('/active', gameController.getActiveGames);

// Get user's games (active, pending, and completed)
router.get('/my-games', gameController.getUserGames);

// Validate game ID (new route for 6-character ID validation)
router.get('/validate/:shortId', gameController.validateGameId);

// Get game details
router.get('/:gameId', gameController.getGame);

// Join a game
router.post('/:gameId/join', gameController.joinGame);

// Start a game
router.put('/:gameId/start', gameController.startGame);

// End a game
router.put('/:gameId/end', gameController.endGame);

// Game action (check, call, raise, fold)
router.post('/:gameId/action', gameController.gameAction);

module.exports = router;