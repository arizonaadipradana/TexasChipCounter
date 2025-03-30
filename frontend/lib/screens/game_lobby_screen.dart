import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/game_model.dart';
import '../models/player_model.dart';
import '../models/user_model.dart';
import '../services/game_service.dart';
import 'active_game_screen.dart';
import 'home_screen.dart';

class GameLobbyScreen extends StatefulWidget {
  final GameModel game;

  const GameLobbyScreen({Key? key, required this.game}) : super(key: key);

  @override
  State<GameLobbyScreen> createState() => _GameLobbyScreenState();
}

class _GameLobbyScreenState extends State<GameLobbyScreen> {
  late GameModel _game;
  bool _isLoading = false;
  late String _shortGameId;
  GameService? _gameService;
  bool _lastUpdateWasGameStart = false;
  UserModel? _userModel; // Nullable to prevent initialization errors

  // Add a flag to track if navigating to game screen to avoid unnecessary cleanup
  bool _navigatingToGameScreen = false;

  @override
  void initState() {
    super.initState();
    _game = widget.game;

    // Use the new method to get the short game ID
    _shortGameId = _game.shortId ?? _game.getShortId();

    // Initialize game service in the next frame after context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGameService();
    });
  }

  void _initializeGameService() {
    // Get user model from provider
    _userModel = Provider.of<UserModel>(context, listen: false);
    if (_userModel?.authToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Authentication error. Please log in again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _gameService = GameService();
    _gameService?.initSocket(_userModel!.authToken!, userId: _userModel?.id);

    // Join the game room for real-time updates
    _gameService?.joinGameRoom(_game.id);

    // Listen for player join/leave events with an enhanced callback
    _gameService?.listenForPlayerUpdates(_handlePlayerUpdate, _handlePlayerKicked);
  }

  // Handle player updates including the short ID
  void _handlePlayerUpdate(GameModel updatedGame) {
    if (mounted) {
      // Log the update for debugging
      print('Received game update: ${updatedGame.players.length} players');
      print('Game status: ${updatedGame.status}');

      // Preserve the short ID when updating the game model
      updatedGame.shortId = _shortGameId;

      // Check if game status changed to active
      if (updatedGame.status == GameStatus.active && _game.status != GameStatus.active) {
        print('Game started, navigating to active game screen');

        // Set this flag to prevent duplicate navigation
        if (_lastUpdateWasGameStart) {
          print('Already handling a game start event, ignoring duplicate');
          return;
        }

        _lastUpdateWasGameStart = true;

        // Set flag to prevent unnecessary cleanup in dispose
        _navigatingToGameScreen = true;

        // Add a small delay to allow all clients to receive the update
        Future.delayed(Duration(milliseconds: 250), () {
          if (mounted) {
            // Navigate to the active game screen
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => ActiveGameScreen(game: updatedGame),
              ),
            );
          }
        });
        return;
      }

      // Check if current player is still in the game
      final currentUserId = _userModel?.id;
      if (currentUserId != null) {
        final stillInGame = updatedGame.players.any((p) => p.userId == currentUserId);

        if (!stillInGame) {
          print('Current player no longer in game, returning to home');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You are no longer in this game'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.of(context).pop();
          return;
        }
      }

      // Calculate what changed for notifications
      final oldPlayerIds = _game.players.map((p) => p.userId).toSet();
      final newPlayerIds = updatedGame.players.map((p) => p.userId).toSet();

      // Players who joined
      final addedPlayers = newPlayerIds.difference(oldPlayerIds);

      // Players who left
      final removedPlayers = oldPlayerIds.difference(newPlayerIds);

      // Update the local game state
      setState(() {
        _game = updatedGame;
      });

      // Show notifications for player changes
      if (addedPlayers.isNotEmpty) {
        // Find names of players who joined
        for (final playerId in addedPlayers) {
          final player = updatedGame.players.firstWhere(
                (p) => p.userId == playerId,
            orElse: () => Player(userId: playerId, username: 'Unknown Player', chipBalance: 0),
          );

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${player.username} joined the game'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }

      if (removedPlayers.isNotEmpty) {
        // Try to find names of removed players from old players list
        for (final playerId in removedPlayers) {
          final oldPlayers = widget.game.players;
          final player = oldPlayers.firstWhere(
                (p) => p.userId == playerId,
            orElse: () => Player(userId: playerId, username: 'A player', chipBalance: 0),
          );

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${player.username} left the game'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }


  void _handlePlayerKicked(String gameId, String kickedBy) {
    // This is called when the current user is kicked
    if (mounted) {
      // Set flag to prevent unnecessary cleanup in dispose
      _navigatingToGameScreen = true;

      // Show message to user
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have been removed from the game'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );

      // Leave the game room (clean up socket connection)
      if (_gameService != null) {
        _gameService!.leaveGameRoom(_game.id);
      }

      // Force navigation to home screen with a slight delay
      Future.delayed(Duration(milliseconds: 300), () {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
                (route) => false, // Remove all previous routes
          );
        }
      });
    }
  }

  void _copyGameId() {
    Clipboard.setData(ClipboardData(text: _shortGameId)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Game ID copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    });
  }

  void _removePlayer(String userId) async {
    final userModel = Provider.of<UserModel>(context, listen: false);
    final isHost = userModel.id == _game.hostId;

    if (!isHost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the host can remove players'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Create a copy of the game with player removed
    final updatedGame = GameModel(
      id: _game.id,
      name: _game.name,
      hostId: _game.hostId,
      players: _game.players.where((p) => p.userId != userId).toList(),
      smallBlind: _game.smallBlind,
      bigBlind: _game.bigBlind,
      createdAt: _game.createdAt,
      status: _game.status,
      currentPlayerIndex: _game.currentPlayerIndex,
      shortId: _shortGameId, // Preserve the short ID
    );

    // Update local state first for responsive UI
    setState(() {
      _game = updatedGame;
    });

    // Notify all connected clients about the player removal
    _gameService?.notifyPlayerRemoved(_game.id, updatedGame, userId);
  }

// Update the startGame method in the lobby screen to show feedback immediately
  Future<void> _startGame() async {
    if (_game.players.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You need at least 2 players to start a game'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Check if services are properly initialized
    if (_gameService == null || _userModel?.authToken == null) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Service not initialized'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Provide immediate feedback that game is starting
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Starting game...'),
        duration: Duration(seconds: 1),
      ),
    );

    // Optimistically update the game status to give immediate feedback
    setState(() {
      // This is a temporary UI update before the server responds
      _game.status = GameStatus.active;
    });

    // Call API to start the game
    final result = await _gameService!.startGame(_game.id, _userModel!.authToken!);

    setState(() {
      _isLoading = false;
    });

    if (result['success']) {
      final updatedGame = result['game'] as GameModel;

      // Preserve the short ID
      updatedGame.shortId = _shortGameId;

      // Set flag to avoid unnecessary cleanup
      _navigatingToGameScreen = true;
      _lastUpdateWasGameStart = true;

      // Navigate to active game screen
      if (mounted) {
        // Add a slight delay to allow socket events to propagate
        Future.delayed(Duration(milliseconds: 100), () {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => ActiveGameScreen(game: updatedGame),
              ),
            );
          }
        });
      }
    } else {
      if (mounted) {
        // Revert the optimistic update if the API call failed
        setState(() {
          _game.status = GameStatus.pending;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    // Only perform cleanup if not navigating to game screen or kicked
    if (!_navigatingToGameScreen && _userModel?.authToken != null) {
      // Check if user is leaving voluntarily and is in the game
      if (_userModel?.id != null && _game.players.any((p) => p.userId == _userModel?.id)) {
        // Create a copy of the game with current player removed
        final updatedPlayers = _game.players.where((p) => p.userId != _userModel?.id).toList();
        final updatedGame = GameModel(
          id: _game.id,
          name: _game.name,
          hostId: _game.hostId,
          players: updatedPlayers,
          smallBlind: _game.smallBlind,
          bigBlind: _game.bigBlind,
          createdAt: _game.createdAt,
          status: _game.status,
          currentPlayerIndex: _game.currentPlayerIndex,
          shortId: _shortGameId, // Preserve the short ID
        );

        // Notify others that player is leaving
        _gameService?.notifyPlayerQuitting(_game.id, updatedGame);
      }

      // Leave the game room
      _gameService?.leaveGameRoom(_game.id);
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userModel = Provider.of<UserModel>(context);
    final isHost = userModel.id == _game.hostId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Game Lobby'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Game Info Card
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      _game.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Game ID: ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(_shortGameId),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          onPressed: _copyGameId,
                          splashRadius: 20,
                          tooltip: 'Copy Game ID',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildInfoItem(
                          icon: Icons.attach_money,
                          label: 'Small Blind',
                          value: '${_game.smallBlind} chips',
                        ),
                        _buildInfoItem(
                          icon: Icons.attach_money,
                          label: 'Big Blind',
                          value: '${_game.bigBlind} chips',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Players Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Players',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_game.players.length}/8',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Player List
            Expanded(
              child: _game.players.isEmpty
                  ? const Center(
                child: Text(
                  'Waiting for players to join...',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
              )
                  : ListView.builder(
                itemCount: _game.players.length,
                itemBuilder: (context, index) {
                  final player = _game.players[index];
                  final isCurrentUser = player.userId == userModel.id;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isCurrentUser ? Colors.blue : Colors.grey.shade700,
                        child: Text(
                          player.username.substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${player.username} ${isCurrentUser ? '(You)' : ''}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (player.userId == _game.hostId)
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Host',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.amber.shade800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text('${player.chipBalance} chips'),
                      trailing: isHost && !isCurrentUser
                          ? IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                        onPressed: () => _removePlayer(player.userId),
                        tooltip: 'Remove player',
                      )
                          : null,
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // Start Game Button (for host only)
            if (isHost) ...[
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _startGame,
                icon: const Icon(Icons.play_arrow),
                label: _isLoading
                    ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    const Text('Starting...'),
                  ],
                )
                    : const Text('Start Game'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ] else ...[
              // Waiting message for non-host players
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Waiting for host to start the game...',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 16,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}