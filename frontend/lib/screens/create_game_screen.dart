import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/user_model.dart';
import '../models/game_model.dart';
import '../models/player_model.dart';
import '../services/game_service.dart';
import 'game_lobby_screen.dart';

class CreateGameScreen extends StatefulWidget {
  const CreateGameScreen({Key? key}) : super(key: key);

  @override
  State<CreateGameScreen> createState() => _CreateGameScreenState();
}

class _CreateGameScreenState extends State<CreateGameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _gameNameController = TextEditingController();
  final _smallBlindController = TextEditingController(text: '5');
  final _bigBlindController = TextEditingController(text: '10');

  bool _isLoading = false;

  @override
  void dispose() {
    _gameNameController.dispose();
    _smallBlindController.dispose();
    _bigBlindController.dispose();
    super.dispose();
  }

  void _createGame() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final userModel = Provider.of<UserModel>(context, listen: false);
      final gameService = GameService();

      // In real app, make API call to create game instead of local creation
      if (userModel.authToken != null) {
        try {
          final result = await gameService.createGame(
            _gameNameController.text.trim(),
            int.parse(_smallBlindController.text),
            int.parse(_bigBlindController.text),
            userModel.authToken!,
          );

          setState(() {
            _isLoading = false;
          });

          if (result['success']) {
            final game = result['game'] as GameModel;

            // Output the game ID and its short version for debugging
            final shortId = game.id.substring(0, 6).toUpperCase();
            print('Created game with ID: ${game.id}');
            print('Short ID for sharing: $shortId');

            // Register the ID for easy lookup
            GameService.registerGameId(game.id);

            // Navigate to the game lobby
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => GameLobbyScreen(game: game),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result['message']),
                backgroundColor: Colors.red,
              ),
            );
          }
        } catch (e) {
          setState(() {
            _isLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error creating game: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        // Fallback to local creation for testing/demo only
        // Note: This shouldn't be used in production
        final gameId = const Uuid().v4();

        // Log and register the ID
        print('Created local test game with ID: $gameId');
        print('Short ID for sharing: ${gameId.substring(0, 6).toUpperCase()}');
        GameService.registerGameId(gameId);

        // Create the player and game objects
        final hostPlayer = Player(
          userId: userModel.id!,
          username: userModel.username!,
          chipBalance: userModel.chipBalance,
        );

        final game = GameModel(
          id: gameId,
          name: _gameNameController.text.trim(),
          hostId: userModel.id!,
          players: [hostPlayer],
          smallBlind: int.parse(_smallBlindController.text),
          bigBlind: int.parse(_bigBlindController.text),
          createdAt: DateTime.now(),
        );

        setState(() {
          _isLoading = false;
        });

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => GameLobbyScreen(game: game),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Game'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _gameNameController,
                decoration: const InputDecoration(
                  labelText: 'Game Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a game name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _smallBlindController,
                      decoration: const InputDecoration(
                        labelText: 'Small Blind (chips)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Required';
                        }
                        final smallBlind = int.tryParse(value);
                        if (smallBlind == null || smallBlind <= 0) {
                          return 'Enter valid amount';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _bigBlindController,
                      decoration: const InputDecoration(
                        labelText: 'Big Blind (chips)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Required';
                        }
                        final bigBlind = int.tryParse(value);
                        if (bigBlind == null || bigBlind <= 0) {
                          return 'Enter valid amount';
                        }
                        final smallBlind = int.tryParse(_smallBlindController.text) ?? 0;
                        if (bigBlind <= smallBlind) {
                          return 'Must be > small blind';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _createGame,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Create Game'),
              ),
              const SizedBox(height: 16),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Game Setup Information:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• 1 chip = 500 rupiah',
                        style: TextStyle(fontSize: 14),
                      ),
                      Text(
                        '• Default small blind is 5 chips (2,500 rupiah)',
                        style: TextStyle(fontSize: 14),
                      ),
                      Text(
                        '• Default big blind is 10 chips (5,000 rupiah)',
                        style: TextStyle(fontSize: 14),
                      ),
                      Text(
                        '• After creating the game, you can invite other players',
                        style: TextStyle(fontSize: 14),
                      ),
                      Text(
                        '• Players will use a 6-character ID to join your game',
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