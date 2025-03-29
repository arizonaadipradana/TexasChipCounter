import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game_model.dart';
import '../models/user_model.dart';
import '../widgets/poker_action_button.dart';

class ActiveGameScreen extends StatefulWidget {
  final GameModel game;

  const ActiveGameScreen({Key? key, required this.game}) : super(key: key);

  @override
  State<ActiveGameScreen> createState() => _ActiveGameScreenState();
}

class _ActiveGameScreenState extends State<ActiveGameScreen> {
  late GameModel _game;
  int _currentPot = 0;
  int _currentBet = 0;
  final TextEditingController _raiseController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _game = widget.game;
    _currentBet = _game.bigBlind; // Initialize with big blind amount
  }

  @override
  void dispose() {
    _raiseController.dispose();
    super.dispose();
  }

  void _nextTurn() {
    setState(() {
      _game.nextTurn();
    });
  }

  void _handleCheck() {
    // In a real app, you would make an API call to update the game state
    _nextTurn();
    _showActionSnackBar('Check');
  }

  void _handleCall() {
    final player = _game.currentPlayer;

    if (player.chipBalance >= _currentBet) {
      setState(() {
        player.removeChips(_currentBet);
        _currentPot += _currentBet;
      });

      _nextTurn();
      _showActionSnackBar('Call: $_currentBet chips');
    } else {
      _showInsufficientChipsDialog();
    }
  }

  void _handleFold() {
    setState(() {
      _game.currentPlayer.setInactive();
    });

    _nextTurn();
    _showActionSnackBar('Fold');
  }

  void _handleRaise() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Raise Amount'),
        content: TextField(
          controller: _raiseController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Min: ${_currentBet * 2}',
            suffixText: 'chips',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final raiseAmount = int.tryParse(_raiseController.text) ?? 0;
              if (raiseAmount < _currentBet * 2) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Raise must be at least ${_currentBet * 2} chips'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              final player = _game.currentPlayer;
              if (player.chipBalance >= raiseAmount) {
                setState(() {
                  player.removeChips(raiseAmount);
                  _currentPot += raiseAmount;
                  _currentBet = raiseAmount;
                });

                _nextTurn();
                Navigator.of(context).pop();
                _showActionSnackBar('Raise: $raiseAmount chips');
              } else {
                Navigator.of(context).pop();
                _showInsufficientChipsDialog();
              }
            },
            child: const Text('Raise'),
          ),
        ],
      ),
    );
  }

  void _showActionSnackBar(String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_game.players[(_game.currentPlayerIndex - 1) % _game.players.length].username} - $action'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showInsufficientChipsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Insufficient Chips'),
        content: const Text('You don\'t have enough chips for this action.'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userModel = Provider.of<UserModel>(context);
    final isCurrentUserTurn = _game.currentPlayer.userId == userModel.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(_game.name),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: Text(
                'Pot: $_currentPot',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Players',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _game.players.length,
                      itemBuilder: (context, index) {
                        final player = _game.players[index];
                        final isCurrentUser = player.userId == userModel.id;
                        final isCurrentTurn = index == _game.currentPlayerIndex;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: isCurrentTurn ? Colors.blue.shade100 : null,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isCurrentTurn ? Colors.blue : Colors.grey,
                              child: Text(
                                player.username.substring(0, 1).toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(
                              '${player.username} ${isCurrentUser ? '(You)' : ''}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text('${player.chipBalance} chips'),
                            trailing: isCurrentTurn
                                ? const Icon(Icons.arrow_forward, color: Colors.blue)
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isCurrentUserTurn) ...[
            Container(
              padding: const EdgeInsets.all(16.0),
              color: Colors.grey.shade200,
              child: Column(
                children: [
                  Text(
                    'Current Bet: $_currentBet chips',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      PokerActionButton(
                        label: 'Fold',
                        color: Colors.red,
                        icon: Icons.close,
                        onPressed: _handleFold,
                      ),
                      PokerActionButton(
                        label: 'Check',
                        color: Colors.amber,
                        icon: Icons.check,
                        onPressed: _handleCheck,
                      ),
                      PokerActionButton(
                        label: 'Call',
                        color: Colors.green,
                        icon: Icons.call,
                        onPressed: _handleCall,
                      ),
                      PokerActionButton(
                        label: 'Raise',
                        color: Colors.purple,
                        icon: Icons.arrow_upward,
                        onPressed: _handleRaise,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16.0),
              color: Colors.grey.shade200,
              child: const Center(
                child: Text(
                  'Waiting for other players...',
                  style: TextStyle(
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}