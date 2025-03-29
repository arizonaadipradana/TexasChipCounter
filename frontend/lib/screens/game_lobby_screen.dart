import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/game_model.dart';
import '../models/user_model.dart';
import '../services/game_service.dart';
import 'active_game_screen.dart';

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
  late GameService _gameService;
  late UserModel _userModel;

  @override
  void initState() {
    super.initState();
    _game = widget.game;
    _shortGameId = _game.id.substring(0, 6).toUpperCase();

    // Register this game ID for future lookups
    GameService.registerGameId(_game.id);

    // Initialize game service in the next frame after context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGameService();
    });
  }

  void _initializeGameService() {
    // Get user model from provider
    _userModel = Provider.of<UserModel>(context, listen: false);
    if (_userModel.authToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Authentication error. Please log in again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _gameService = GameService();
    _gameService.initSocket(_userModel.authToken!);

    // Join the game room for real-time updates
    _gameService.joinGameRoom(_game.id);

    // Listen for player join/leave events
    _gameService.listenForPlayerUpdates(_handlePlayerUpdate);
  }

  void _handlePlayerUpdate(GameModel updatedGame) {
    if (mounted) {
      setState(() {
        _game = updatedGame;
      });

      // Show a snack bar notification when a player joins or leaves
      final playerCount = _game.players.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Game updated: $playerCount ${playerCount == 1 ? "player" : "players"} in lobby'),
          duration: const Duration(seconds: 1),
        ),
      );
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

    // Call API to start the game
    final result = await _gameService.startGame(_game.id, _userModel.authToken!);

    setState(() {
      _isLoading = false;
    });

    if (result['success']) {
      final updatedGame = result['game'] as GameModel;

      // Navigate to active game screen
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ActiveGameScreen(game: updatedGame),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _removePlayer(String userId) async {
    // Remove the player from the local model
    setState(() {
      _game.removePlayer(userId);
    });

    // Notify all connected players about the removal
    _gameService.notifyPlayerRemoved(_game.id, _game);
  }

  @override
  void dispose() {
    // Leave the game room and disconnect socket when leaving the screen
    if (_userModel.authToken != null) {
      _gameService.leaveGameRoom(_game.id);
      _gameService.disconnectSocket();
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