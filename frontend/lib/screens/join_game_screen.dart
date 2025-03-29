import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game_model.dart';
import '../models/user_model.dart';
import '../services/game_service.dart';
import 'game_lobby_screen.dart';

class JoinGameScreen extends StatefulWidget {
  const JoinGameScreen({Key? key}) : super(key: key);

  @override
  State<JoinGameScreen> createState() => _JoinGameScreenState();
}

class _JoinGameScreenState extends State<JoinGameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _gameIdController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';
  late GameService _gameService;

  @override
  void initState() {
    super.initState();
    _gameService = GameService();
    // Initialize the game service
    final userModel = Provider.of<UserModel>(context, listen: false);
    if (userModel.authToken != null) {
      _gameService.initSocket(userModel.authToken!);

      // Pre-fetch available games in the background
      _prefetchGames(userModel.authToken!);
    }
  }

  Future<void> _prefetchGames(String authToken) async {
    try {
      // This is just to pre-populate the game ID map with existing games
      await _gameService.getAllGames(authToken);
    } catch (e) {
      print('Error prefetching games: $e');
      // Don't show error to user, this is just a background operation
    }
  }

  @override
  void dispose() {
    _gameIdController.dispose();
    _gameService.disconnectSocket();
    super.dispose();
  }

  Future<void> _joinGame() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      final gameId = _gameIdController.text.trim().toUpperCase();
      final userModel = Provider.of<UserModel>(context, listen: false);

      print('Attempting to join game with ID: $gameId');

      if (userModel.authToken == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'You need to log in first';
        });
        return;
      }

      try {
        // Show a temporary message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Validating game ID...'),
            duration: Duration(seconds: 1),
          ),
        );

        // First validate the game ID
        final validation = await _gameService.validateGameId(gameId, userModel.authToken!);
        print('Game validation result: $validation');

        if (!validation['exists']) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Game not found. Please check the ID and try again.';
          });
          return;
        }

        // Show another temporary message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Game found! Joining now...'),
            duration: Duration(seconds: 1),
          ),
        );

        // Now try to join the game
        final result = await _gameService.joinGame(gameId, userModel.authToken!);
        print('Join game result: $result');

        setState(() {
          _isLoading = false;
        });

        if (result['success']) {
          final game = result['game'] as GameModel;
          final alreadyJoined = result['alreadyJoined'] == true;

          if (alreadyJoined) {
            print('Player was already in the game, rejoining lobby');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You are already in this game. Rejoining lobby...'),
                duration: Duration(seconds: 2),
              ),
            );
          } else {
            print('Successfully joined game as new player');
          }

          // Navigate to the game lobby in either case
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => GameLobbyScreen(game: game),
              ),
            );
          }
        } else {
          setState(() {
            _errorMessage = result['message'];
          });
        }
      } catch (e) {
        print('Error in join game process: $e');
        setState(() {
          _isLoading = false;
          _errorMessage = 'An error occurred: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Game'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _gameIdController,
                decoration: const InputDecoration(
                  labelText: 'Game ID',
                  border: OutlineInputBorder(),
                  hintText: 'Enter the 6-character Game ID',
                  prefixIcon: Icon(Icons.games),
                ),
                maxLength: 6,
                textCapitalization: TextCapitalization.characters,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a Game ID';
                  }
                  if (value.length != 6) {
                    return 'Game ID must be 6 characters';
                  }
                  return null;
                },
              ),

              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _joinGame,
                icon: const Icon(Icons.login),
                label: _isLoading
                    ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Joining...'),
                  ],
                )
                    : const Text('Join Game'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How to join a game:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '1. Ask the game host for the 6-character Game ID',
                        style: TextStyle(fontSize: 14),
                      ),
                      Text(
                        '2. Enter the Game ID above (case-insensitive)',
                        style: TextStyle(fontSize: 14),
                      ),
                      Text(
                        '3. Tap "Join Game" to enter the game lobby',
                        style: TextStyle(fontSize: 14),
                      ),
                      Text(
                        '4. Wait for the host to start the game',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}