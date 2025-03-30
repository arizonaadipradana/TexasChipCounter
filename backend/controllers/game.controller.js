const Game = require('../models/game.model');
const User = require('../models/user.model');
const GameId = require('../models/game_id.model');
const Transaction = require('../models/transaction.model');
const mongoose = require('mongoose');

// Create a new game with unique ID
exports.createGame = async (req, res) => {
  try {
    console.log("Create game request received");
    const { name, smallBlind, bigBlind } = req.body;
    const hostId = req.userId;

    // Validate game data
    if (!name || !smallBlind || !bigBlind) {
      return res.status(400).json({
        success: false,
        message: 'Name, smallBlind, and bigBlind are required'
      });
    }

    // Get host user
    const hostUser = await User.findById(hostId);
    if (!hostUser) {
      return res.status(404).json({
        success: false,
        message: 'Host user not found'
      });
    }

    console.log("Creating game object");

    // Generate a temporary 6-character ID
    const charset = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let shortId = '';
    for (let i = 0; i < 6; i++) {
      shortId += charset.charAt(Math.floor(Math.random() * charset.length));
    }
    console.log(`Generated short ID: ${shortId}`);

    // Store the short ID directly in the game document (as a temporary solution)
    // Create game
    const game = new Game({
      name,
      hostId,
      shortId, // Add shortId directly to the game document as a temporary solution
      smallBlind: parseInt(smallBlind),
      bigBlind: parseInt(bigBlind),
      players: [{
        userId: hostUser._id,
        username: hostUser.username,
        chipBalance: hostUser.chipBalance,
        isActive: true,
        position: 0
      }]
    });

    console.log("Saving game to database");
    // Save game
    const savedGame = await game.save();

    // Return success response with the game and short ID
    return res.status(201).json({
      success: true,
      message: 'Game created successfully (with temporary ID)',
      game: savedGame,
      shortId: shortId
    });
  } catch (error) {
    console.error('Create game error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to create game',
      error: error.message
    });
  }
};

// Join a game
exports.joinGame = async (req, res) => {
  try {
    const { gameId } = req.params;
    const userId = req.userId;

    console.log(`Attempting to join game with ID: ${gameId}`);

    // Find game - could be full MongoDB ID or shortId
    let game;

    // First try to find by MongoDB ObjectId
    if (mongoose.Types.ObjectId.isValid(gameId)) {
      game = await Game.findById(gameId);
    }

    // If not found, try by shortId
    if (!game && gameId.length === 6) {
      game = await Game.findOne({ shortId: gameId.toUpperCase() });
    }

    if (!game) {
      return res.status(404).json({
        success: false,
        message: 'Game not found'
      });
    }

    // Check if game is open for joining
    if (game.status !== 'pending') {
      return res.status(400).json({
        success: false,
        message: 'Cannot join a game that has already started or ended'
      });
    }

    // Get joining user
    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    // Check if user is already in the game
    const existingPlayer = game.players.find(
      player => player.userId.toString() === userId.toString()
    );

    if (existingPlayer) {
      return res.status(200).json({
        success: true,
        message: 'You are already in this game',
        game,
        alreadyJoined: true
      });
    }

    // Add player to game
    game.addPlayer({
      userId: user._id,
      username: user.username,
      chipBalance: user.chipBalance,
      isActive: true,
      position: game.players.length
    });

    // Save game
    await game.save();

    return res.status(200).json({
      success: true,
      message: 'Successfully joined the game',
      game
    });
  } catch (error) {
    console.error('Join game error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to join game',
      error: error.message
    });
  }
};

// Get game details with short ID information
exports.getGame = async (req, res) => {
  try {
    const { gameId } = req.params;

    // Find game
    const game = await Game.findById(gameId);
    if (!game) {
      return res.status(404).json({
        success: false,
        message: 'Game not found'
      });
    }

    // Find the short ID for this game
    const gameIdRecord = await GameId.findOne({ fullId: game._id });
    const shortId = gameIdRecord ? gameIdRecord.shortId : null;

    // Add the short ID to the response
    const gameResponse = game.toObject();
    gameResponse.shortId = shortId;

    return res.status(200).json({
      success: true,
      game: gameResponse
    });
  } catch (error) {
    console.error('Get game error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to get game details',
      error: error.message
    });
  }
};

// Start a game
exports.startGame = async (req, res) => {
  try {
    const { gameId } = req.params;
    const userId = req.userId;

    // Find game
    const game = await Game.findById(gameId);
    if (!game) {
      return res.status(404).json({
        success: false,
        message: 'Game not found'
      });
    }

    // Check if user is the host
    if (game.hostId.toString() !== userId.toString()) {
      return res.status(403).json({
        success: false,
        message: 'Only the host can start the game'
      });
    }

    // Check if game is already started
    if (game.status !== 'pending') {
      return res.status(400).json({
        success: false,
        message: 'Game has already started or ended'
      });
    }

    // Check if there are enough players
    if (game.players.length < 2) {
      return res.status(400).json({
        success: false,
        message: 'Need at least 2 players to start a game'
      });
    }

    // Start game
    game.startGame();

    // Save game with updated status
    const savedGame = await game.save();

    // Get the io instance to broadcast updates to all connected clients
    const io = req.app.get('io');
    if (io) {
      // Emit a specific game_started event to all clients in this game room
      console.log(`Broadcasting game_started event to room: ${gameId}`);
      io.to(gameId).emit('game_started', {
        gameId,
        action: 'game_started',
        message: 'Game has started!',
        game: savedGame.toObject(),
        timestamp: new Date().toISOString()
      });

      // Also emit a general game_update event for clients that might not be listening to game_started
      io.to(gameId).emit('game_update', {
        gameId,
        action: 'game_update',
        message: 'Game has started!',
        game: savedGame.toObject(),
        timestamp: new Date().toISOString()
      });
    }

    return res.status(200).json({
      success: true,
      message: 'Game started successfully',
      game: savedGame
    });
  } catch (error) {
    console.error('Start game error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to start game',
      error: error.message
    });
  }
};

// Game action (check, call, raise, fold)
exports.gameAction = async (req, res) => {
  try {
    const { gameId } = req.params;
    const { action, amount } = req.body;
    const userId = req.userId;

    // Find game
    const game = await Game.findById(gameId);
    if (!game) {
      return res.status(404).json({
        success: false,
        message: 'Game not found'
      });
    }

    // Check if game is active
    if (game.status !== 'active') {
      return res.status(400).json({
        success: false,
        message: 'Game is not active'
      });
    }

    // Check if it's the user's turn
    const currentPlayer = game.players[game.currentPlayerIndex];
    if (currentPlayer.userId.toString() !== userId.toString()) {
      return res.status(403).json({
        success: false,
        message: 'It\'s not your turn'
      });
    }

    // Process game action
    let actionResult = false;
    let actionMessage = '';

    switch (action) {
      case 'check':
        // No chip changes for check
        actionResult = true;
        actionMessage = 'Check';
        break;

      case 'call':
        // Deduct current bet amount from player's balance
        if (currentPlayer.chipBalance >= game.currentBet) {
          game.pot += game.currentBet;
          actionResult = game.updatePlayerChips(userId, -game.currentBet);
          actionMessage = `Call: ${game.currentBet} chips`;

          // Create transaction record
          await Transaction.createGameTransaction(
            userId,
            -game.currentBet,
            gameId,
            `Call in game: ${game.name}`
          );
        } else {
          return res.status(400).json({
            success: false,
            message: 'Not enough chips to call'
          });
        }
        break;

      case 'raise':
        // Validate raise amount
        const raiseAmount = parseInt(amount);
        if (!raiseAmount || raiseAmount < game.currentBet * 2) {
          return res.status(400).json({
            success: false,
            message: `Raise must be at least ${game.currentBet * 2} chips`
          });
        }

        // Check if player has enough chips
        if (currentPlayer.chipBalance >= raiseAmount) {
          game.pot += raiseAmount;
          game.currentBet = raiseAmount;
          actionResult = game.updatePlayerChips(userId, -raiseAmount);
          actionMessage = `Raise: ${raiseAmount} chips`;

          // Create transaction record
          await Transaction.createGameTransaction(
            userId,
            -raiseAmount,
            gameId,
            `Raise in game: ${game.name}`
          );
        } else {
          return res.status(400).json({
            success: false,
            message: 'Not enough chips to raise'
          });
        }
        break;

      case 'fold':
        // Mark player as inactive
        currentPlayer.isActive = false;
        actionResult = true;
        actionMessage = 'Fold';
        break;

      default:
        return res.status(400).json({
          success: false,
          message: 'Invalid action'
        });
    }

    if (actionResult) {
      // Move to next player's turn
      const oldPlayerIndex = game.currentPlayerIndex;
      game.nextTurn();

      // Log the player turn change
      console.log(`Game ${gameId}: Player turn changed from index ${oldPlayerIndex} to ${game.currentPlayerIndex}`);

      // Save game
      await game.save();

      // Get io instance from request
      const io = req.app.get('io');
      if (io) {
        // Emit detailed action information
        io.to(gameId).emit('game_action_performed', {
          gameId,
          action: 'game_action_performed',
          actionType: action,
          amount: action === 'raise' ? amount : game.currentBet,
          player: currentPlayer.username,
          previousPlayerIndex: oldPlayerIndex,
          currentPlayerIndex: game.currentPlayerIndex,
          game: game.toObject(),
          timestamp: new Date().toISOString()
        });

        // Also emit a specific turn_changed event to update UI immediately
        io.to(gameId).emit('turn_changed', {
          gameId,
          action: 'turn_changed',
          previousPlayerIndex: oldPlayerIndex,
          currentPlayerIndex: game.currentPlayerIndex,
          game: game.toObject(),
          timestamp: new Date().toISOString()
        });
      }

      return res.status(200).json({
        success: true,
        message: actionMessage,
        game: game.toObject()
      });
    } else {
      return res.status(400).json({
        success: false,
        message: 'Failed to process action'
      });
    }
  } catch (error) {
    console.error('Game action error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to process game action',
      error: error.message
    });
  }
};

// End a game
exports.endGame = async (req, res) => {
  try {
    const { gameId } = req.params;
    const userId = req.userId;

    // Find game
    const game = await Game.findById(gameId);
    if (!game) {
      return res.status(404).json({
        success: false,
        message: 'Game not found'
      });
    }

    // Check if user is the host
    if (game.hostId.toString() !== userId.toString()) {
      return res.status(403).json({
        success: false,
        message: 'Only the host can end the game'
      });
    }

    // Check if game is active
    if (game.status !== 'active') {
      return res.status(400).json({
        success: false,
        message: 'Game is not active'
      });
    }

    // End game
    game.endGame();

    // We've removed the GameId model, so we don't need to mark it inactive
    // Just save the game with the completed status
    await game.save();

    return res.status(200).json({
      success: true,
      message: 'Game ended successfully',
      game
    });
  } catch (error) {
    console.error('End game error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to end game',
      error: error.message
    });
  }
};


// Get active games
exports.getActiveGames = async (req, res) => {
  try {
    const userId = req.userId;

    // Find all active games where the user is a player
    const games = await Game.find({
      status: 'active',
      'players.userId': userId
    }).sort({ updatedAt: -1 });

    return res.status(200).json({
      success: true,
      games
    });
  } catch (error) {
    console.error('Get active games error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to get active games',
      error: error.message
    });
  }
};

// Get user's games (active, pending, and completed)
exports.getUserGames = async (req, res) => {
  try {
    const userId = req.userId;
    const status = req.query.status; // Optional filter by status

    // Build query
    let query = { 'players.userId': userId };
    if (status && ['active', 'pending', 'completed'].includes(status)) {
      query.status = status;
    }

    // Find games
    const games = await Game.find(query).sort({ updatedAt: -1 });

    return res.status(200).json({
      success: true,
      games
    });
  } catch (error) {
    console.error('Get user games error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to get user games',
      error: error.message
    });
  }
};

// Get all games
exports.getAllGames = async (req, res) => {
  try {
    const status = req.query.status;
    let query = {};

    // If status is specified and not 'all', filter by status
    if (status && status !== 'all') {
      if (!['pending', 'active', 'completed'].includes(status)) {
        return res.status(400).json({
          success: false,
          message: 'Invalid status parameter',
          games: []
        });
      }
      query.status = status;
    }

    // Find games based on query
    const games = await Game.find(query).sort({ updatedAt: -1 });

    return res.status(200).json({
      success: true,
      games
    });
  } catch (error) {
    console.error('Get all games error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to get games',
      error: error.message
    });
  }
};

// Validate a short game ID
exports.validateGameId = async (req, res) => {
  try {
    const { shortId } = req.params;

    if (!shortId || shortId.length !== 6) {
      return res.status(400).json({
        success: false,
        message: 'Invalid short ID format',
        exists: false
      });
    }

    console.log(`Validating game ID: ${shortId}`);

    // Find game directly using shortId
    const game = await Game.findOne({ shortId: shortId.toUpperCase() });

    if (!game) {
      console.log(`No game found with shortId: ${shortId}`);
      return res.status(200).json({
        success: true,
        exists: false,
        message: 'No game found with this ID'
      });
    }

    console.log(`Found game with ID: ${game._id} for shortId: ${shortId}`);

    // Return the game's MongoDB ID
    return res.status(200).json({
      success: true,
      exists: true,
      gameId: game._id.toString()
    });
  } catch (error) {
    console.error('Validate game ID error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to validate game ID',
      error: error.message,
      exists: false
    });
  }
};

exports.removePlayer = async (req, res) => {
  try {
    const { gameId, userId } = req.params;
    const hostId = req.userId;

    // Find game
    const game = await Game.findById(gameId);
    if (!game) {
      return res.status(404).json({
        success: false,
        message: 'Game not found'
      });
    }

    // Check if user is the host
    if (game.hostId.toString() !== hostId.toString()) {
      return res.status(403).json({
        success: false,
        message: 'Only the host can remove players'
      });
    }

    // Check if player exists in the game
    const playerExists = game.players.some(
      player => player.userId.toString() === userId.toString()
    );

    if (!playerExists) {
      return res.status(404).json({
        success: false,
        message: 'Player not found in the game'
      });
    }

    // Remove player
    game.removePlayer(userId);
    await game.save();

    // Return updated game
    return res.status(200).json({
      success: true,
      message: 'Player removed successfully',
      game
    });
  } catch (error) {
    console.error('Remove player error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to remove player',
      error: error.message
    });
  }
};