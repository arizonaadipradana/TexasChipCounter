import 'dart:async';
import 'dart:math' as Math;

import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/api_config.dart';

class SocketManager {
  // Singleton instance
  static final SocketManager _instance = SocketManager._internal();
  factory SocketManager() => _instance;
  SocketManager._internal();

  // Socket instance and state
  io.Socket? _socket;
  String? _userId;
  String? _authToken;
  bool _isConnected = false;

  // Track socket connection status with timer
  Timer? _heartbeatTimer;
  DateTime? _lastEventReceived;

  // Track event listeners to avoid duplicates
  final Map<String, Set<Function(dynamic)>> _eventListeners = {};

  // Track rooms the socket has joined
  final Set<String> _joinedRooms = {};

  // Track last received game state to compare for changes
  Map<String, dynamic>? _lastGameState;

  // Pending events to emit after reconnection
  final List<Map<String, dynamic>> _pendingEvents = [];

  // Callback to be called when significant state changes are detected
  Function(Map<String, dynamic>)? _onStateChange;

  // Track specific events that need extra reliability
  final Set<String> _criticalEventsSent = {};

  // Track game state versions to detect changes
  final Map<String, int> _gameStateVersions = {};

  /// Initialize the socket connection if not already connected
  /// Initialize the socket connection with better reliability
  void initSocket(String authToken, {String? userId}) {
    // Only initialize once if already connected with the same auth token
    if (_socket != null && _isConnected && _authToken == authToken) {
      print('Socket already connected with the same token, skipping initialization');
      return;
    }

    // Store user info
    _authToken = authToken;
    _userId = userId;

    // Disconnect existing socket if any
    if (_socket != null) {
      print('Disconnecting existing socket before creating a new one');
      _socket!.disconnect();
      _socket = null;
    }

    print('Creating new socket connection to: ${ApiConfig.baseUrl}');

    // Create new socket with aggressive reconnection policy
    _socket = io.io(ApiConfig.baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'extraHeaders': {'Authorization': 'Bearer $_authToken'},
      'forceNew': true,  // Force new connection
      'reconnection': true,
      'reconnectionAttempts': 20,  // More reconnection attempts
      'reconnectionDelay': 500,    // Faster initial reconnection
      'reconnectionDelayMax': 3000, // Lower max delay
      'timeout': 10000,           // Quicker timeout
      'pingTimeout': 20000,
      'pingInterval': 5000,       // More frequent ping
    });

    // Connect and set up event handlers
    _socket!.connect();

    _socket!.onConnect((_) {
      print('Socket connected with ID: ${_socket!.id}');
      _isConnected = true;
      _lastEventReceived = DateTime.now();

      // Authenticate the socket connection
      _socket!.emit('authenticate', {'token': _authToken});

      // Rejoin any rooms that were previously joined
      for (final roomId in _joinedRooms) {
        print('Rejoining room: $roomId');
        _socket!.emit('join_game', roomId);
      }

      // Send any pending events
      _processPendingEvents();

      // Start heartbeat monitoring
      _startHeartbeatMonitor();

      // Request fresh state for all joined rooms
      _requestFreshStateForAllRooms();
    });

    _socket!.onDisconnect((_) {
      print('Socket disconnected');
      _isConnected = false;
      _heartbeatTimer?.cancel();

      // Try to reconnect immediately
      Future.delayed(Duration(milliseconds: 1000), () {
        if (!_isConnected && _socket != null) {
          print('Attempting immediate reconnect after disconnect...');
          _socket!.connect();
        }
      });
    });

    _socket!.onError((error) {
      print('Socket error: $error');

      // Force reconnect on error
      Future.delayed(Duration(milliseconds: 1000), () {
        forceReconnect();
      });
    });

    _socket!.onConnectError((error) {
      print('Socket connection error: $error');

      // Try to reconnect after a short delay
      Future.delayed(Duration(milliseconds: 1000), () {
        if (!_isConnected && _socket != null) {
          print('Attempting to reconnect socket after connection error...');
          _socket!.connect();
        }
      });
    });

    // Set up reconnection handlers
    _socket!.on('reconnect', (_) {
      print('Socket reconnected');
      _lastEventReceived = DateTime.now();

      // Re-authenticate
      _socket!.emit('authenticate', {'token': _authToken});

      // Rejoin all rooms
      for (final roomId in _joinedRooms) {
        print('Rejoining room after reconnect: $roomId');
        _socket!.emit('join_game', roomId);

        // Also request a state refresh for each room
        _socket!.emit('game_action', {
          'gameId': roomId,
          'action': 'request_refresh',
          'timestamp': DateTime.now().toIso8601String()
        });
      }

      // Send any pending events
      _processPendingEvents();

      // Restart heartbeat monitoring
      _startHeartbeatMonitor();
    });

    // Add a catchall handler for any event to update _lastEventReceived
    _socket!.onAny((event, data) {
      _lastEventReceived = DateTime.now();

      // If this is a game update, check for state changes
      if ((event == 'game_update' ||
          event == 'game_action_performed' ||
          event == 'turn_changed') &&
          data != null &&
          data['game'] != null &&
          _onStateChange != null) {

        // Compare with last state to detect significant changes
        _detectAndNotifyStateChanges(event, data);
      }
    });
  }

  // Improved state change detection
  void _detectAndNotifyStateChanges(String event, dynamic data) {
    if (data == null || data['game'] == null) return;

    // Get current game state version
    final gameId = data['gameId'];
    final currentVersion = _gameStateVersions[gameId] ?? 0;

    // Check for critical state changes
    bool criticalChange = false;

    // Check for player index change (turn change)
    if (_lastGameState != null && _lastGameState!['currentPlayerIndex'] != null) {
      final oldPlayerIndex = _lastGameState!['currentPlayerIndex'];
      final newPlayerIndex = data['game']['currentPlayerIndex'];

      if (oldPlayerIndex != newPlayerIndex) {
        criticalChange = true;
      }
    }

    // Check for pot amount change (indicates a bet/call/etc)
    if (_lastGameState != null && _lastGameState!['pot'] != null) {
      final oldPot = _lastGameState!['pot'];
      final newPot = data['game']['pot'];

      if (oldPot != newPot) {
        criticalChange = true;
      }
    }

    // Check for game status change
    if (_lastGameState != null && _lastGameState!['status'] != null) {
      final oldStatus = _lastGameState!['status'];
      final newStatus = data['game']['status'];

      if (oldStatus != newStatus) {
        criticalChange = true;
      }
    }

    // Update the last game state
    _lastGameState = data['game'];

    // Increment version for this game state
    _gameStateVersions[gameId] = currentVersion + 1;

    // Notify about the change if it's critical
    if (criticalChange && _onStateChange != null) {
      // Add version to data for tracking
      data['stateVersion'] = _gameStateVersions[gameId];
      _onStateChange!(data);

      print('Notifying about critical state change - ' +
          'Event: $event, Version: ${_gameStateVersions[gameId]}');
    }
  }

  // Request fresh state for all joined rooms
  void _requestFreshStateForAllRooms() {
    if (_joinedRooms.isEmpty) return;

    for (final roomId in _joinedRooms) {
      // Add slight delay to avoid flooding the server
      Future.delayed(Duration(milliseconds: 300 * _joinedRooms.toList().indexOf(roomId)), () {
        if (_isConnected) {
          print('Requesting fresh state for room: $roomId');
          _socket!.emit('game_action', {
            'gameId': roomId,
            'action': 'request_refresh',
            'timestamp': DateTime.now().toIso8601String()
          });
        }
      });
    }
  }

  // Start a heartbeat monitor to detect stale connections
  void _startHeartbeatMonitor() {
    _heartbeatTimer?.cancel();

    _heartbeatTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (_socket == null || !_isConnected) {
        timer.cancel();
        return;
      }

      // Check if we've received events recently
      final now = DateTime.now();
      if (_lastEventReceived != null) {
        final timeSinceLastEvent = now.difference(_lastEventReceived!);

        // If no events for 15 seconds, force reconnect
        if (timeSinceLastEvent.inSeconds > 15) {
          print('No events received for ${timeSinceLastEvent.inSeconds} seconds, forcing reconnect');
          forceReconnect();
        }
      }

      // Emit a ping to keep connection alive
      _socket!.emit('ping', {'timestamp': now.toIso8601String()});

      // Request fresh state for active games periodically (every 20 seconds)
      if (now.second % 20 == 0) {
        _requestFreshStateForAllRooms();
      }
    });
  }

  // Process any pending events that were queued during disconnection
  void _processPendingEvents() {
    if (_pendingEvents.isEmpty) return;

    print('Processing ${_pendingEvents.length} pending events');

    // Clone the list to avoid modification during iteration
    final events = List<Map<String, dynamic>>.from(_pendingEvents);
    _pendingEvents.clear();

    for (final eventData in events) {
      final eventName = eventData['event'];
      final data = eventData['data'];

      print('Emitting pending event: $eventName');
      _socket!.emit(eventName, data);
    }
  }

  // Set a callback to be notified when game state changes
  void setStateChangeCallback(Function(Map<String, dynamic>) callback) {
    _onStateChange = callback;
  }

  /// Join a game room and track it
  void joinGameRoom(String gameId) {
    if (_socket == null) {
      print('Socket is null, cannot join room: $gameId');

      // Store the room ID to join later when socket is initialized
      _joinedRooms.add(gameId);
      return;
    }

    if (!_isConnected) {
      print('Socket not connected, storing room to join later: $gameId');

      // Store the room ID to join later when connected
      _joinedRooms.add(gameId);

      // Try to connect
      _socket!.connect();
      return;
    }

    // Check if already in this room
    if (_joinedRooms.contains(gameId)) {
      print('Already in game room: $gameId, skipping join');

      // Even if already joined, request a fresh state to ensure sync
      _socket!.emit('game_action', {
        'gameId': gameId,
        'action': 'request_refresh',
        'timestamp': DateTime.now().toIso8601String()
      });

      return;
    }

    print('Joining game room: $gameId');
    _socket!.emit('join_game', gameId);
    _joinedRooms.add(gameId);

    // Request initial state refresh
    _socket!.emit('game_action', {
      'gameId': gameId,
      'action': 'request_refresh',
      'timestamp': DateTime.now().toIso8601String()
    });

    // Clear any stored state version for this game
    _gameStateVersions[gameId] = 0;
  }

  /// Force a reconnection of the socket
  void forceReconnect() {
    print('Forcing socket reconnection to fix sync issues');

    if (_socket != null && _authToken != null) {
      // Keep track of current rooms before disconnecting
      final rooms = Set<String>.from(_joinedRooms);

      // Disconnect
      _socket!.disconnect();

      // Clear cached state data
      _lastGameState = null;
      _criticalEventsSent.clear();

      // Wait a moment before reconnecting
      Future.delayed(Duration(milliseconds: 500), () {
        // Create a new connection with same auth token
        initSocket(_authToken!, userId: _userId);

        // Rejoin all the rooms after a short delay
        Future.delayed(Duration(milliseconds: 1000), () {
          for (final roomId in rooms) {
            joinGameRoom(roomId);
          }

          print('Socket reconnected and rooms rejoined');
        });
      });
    }
  }

  /// Leave a game room and remove from tracking
  void leaveGameRoom(String gameId) {
    if (_socket == null) {
      print('Socket is null, cannot leave room: $gameId');
      _joinedRooms.remove(gameId);
      return;
    }

    if (!_isConnected) {
      print('Socket not connected, just removing from tracked rooms: $gameId');
      _joinedRooms.remove(gameId);
      return;
    }

    print('Leaving game room: $gameId');
    _socket!.emit('leave_game', gameId);
    _joinedRooms.remove(gameId);

    // Clear any stored state version for this game
    _gameStateVersions.remove(gameId);
  }

  /// Emit an event with enhanced reliability
  void emit(String event, dynamic data) {
    print('Emitting $event event with data: ${data.toString().substring(0, Math.min(100, data.toString().length))}...');

    if (_socket == null) {
      print('Socket is null, queuing event for later: $event');
      _pendingEvents.add({
        'event': event,
        'data': data,
      });

      // Try to initialize socket if possible
      if (_authToken != null) {
        print('Attempting to initialize socket for pending event');
        initSocket(_authToken!);
      }
      return;
    }

    if (!_isConnected) {
      print('Socket not connected, queuing event: $event');
      _pendingEvents.add({
        'event': event,
        'data': data,
      });

      // Multiple retries with increasing delays
      for (int i = 0; i < 5; i++) {
        Future.delayed(Duration(milliseconds: 500 * (i + 1)), () {
          if (_socket != null && _isConnected) {
            print('Socket connected, emitting delayed event: $event (attempt ${i+1})');
            _socket!.emit(event, data);
          }
        });
      }

      return;
    }

    // Send the event
    _socket!.emit(event, data);

    // For game actions, use multiple emits for reliability
    if (event == 'game_action' && data['gameId'] != null) {
      final gameId = data['gameId'];
      final actionType = data['action'];

      // Create a unique key for this critical event
      String? eventKey;
      if (actionType == 'game_action_performed' ||
          actionType == 'turn_changed' ||
          actionType == 'game_started') {
        // Create a unique key for this event to avoid duplicate broadcasts
        eventKey = '$gameId:$actionType:${DateTime.now().millisecondsSinceEpoch}';

        // If we've already sent this critical event in the last 2 seconds, skip duplicates
        if (_criticalEventsSent.contains(eventKey)) {
          print('Skipping duplicate critical event: $eventKey');
          return;
        }

        // Add to sent events set and schedule removal after 2 seconds
        _criticalEventsSent.add(eventKey);
        Future.delayed(Duration(seconds: 2), () {
          _criticalEventsSent.remove(eventKey);
        });

        // Emit multiple times with delays to ensure delivery
        for (int i = 1; i <= 3; i++) {
          Future.delayed(Duration(milliseconds: 200 * i), () {
            if (_isConnected) {
              _socket!.emit(event, data);
            }
          });
        }

        // Also request all clients to refresh their state
        Future.delayed(Duration(milliseconds: 500), () {
          if (_isConnected) {
            _socket!.emit('game_action', {
              'gameId': gameId,
              'action': 'request_refresh',
              'timestamp': DateTime.now().toIso8601String()
            });
          }
        });
      }
    }
  }

  /// Add event listener with enhanced reliability
  void on(String event, Function(dynamic) handler) {
    if (_socket == null) {
      print('Socket is null, cannot add listener for event: $event');
      return;
    }

    // Add to our tracking map
    if (!_eventListeners.containsKey(event)) {
      _eventListeners[event] = {};
    }

    // Always register the handler - even if it appears to be a duplicate
    _eventListeners[event]!.add(handler);

    // Add handler to socket
    _socket!.on(event, handler);

    print('Added listener for event: $event, total handlers: ${_eventListeners[event]!.length}');
  }

  /// Remove specific event listener
  void off(String event, Function(dynamic) handler) {
    if (_socket == null) {
      print('Socket is null, cannot remove listener for event: $event');
      return;
    }

    // Remove from our tracking
    if (_eventListeners.containsKey(event)) {
      _eventListeners[event]!.remove(handler);
    }

    // With Socket.IO client in Flutter, we can't remove specific listeners
    // We need to remove all and re-add the remaining ones
    _socket!.off(event);

    // Re-add remaining listeners
    if (_eventListeners.containsKey(event) && _eventListeners[event]!.isNotEmpty) {
      for (final remainingHandler in _eventListeners[event]!) {
        if (remainingHandler != handler) {
          _socket!.on(event, remainingHandler);
        }
      }
    }

    print('Removed listener for event: $event');
  }

  /// Clear all listeners for an event
  void clearListeners(String event) {
    if (_socket == null) {
      print('Socket is null, cannot clear listeners for event: $event');
      return;
    }

    // Clear from socket
    _socket!.off(event);

    // Clear from our tracking
    if (_eventListeners.containsKey(event)) {
      _eventListeners[event]!.clear();
    }

    print('Cleared all listeners for event: $event');
  }

  /// Disconnect socket and clean up
  void disconnect() {
    if (_socket != null) {
      // Leave all rooms first
      for (final roomId in _joinedRooms.toList()) {
        leaveGameRoom(roomId);
      }

      _socket!.disconnect();
      _socket = null;
      _isConnected = false;
      _eventListeners.clear();
      _joinedRooms.clear();
      _pendingEvents.clear();
      _gameStateVersions.clear();
      _criticalEventsSent.clear();
      print('Socket manager disconnected and reset');
    }
  }

  void clearRoomOnKick(String gameId) {
    // Remove this room from tracked rooms
    _joinedRooms.remove(gameId);
    _gameStateVersions.remove(gameId);

    // If socket exists and is connected, explicitly leave
    if (_socket != null && _isConnected) {
      _socket!.emit('leave_game', gameId);
    }

    print('Room $gameId cleared due to kick');
  }

  // Add getter for auth token
  String? get authToken => _authToken;

  /// Check if a specific room is joined
  bool isInRoom(String roomId) {
    return _joinedRooms.contains(roomId);
  }

  /// Get all joined rooms
  Set<String> get joinedRooms => Set.from(_joinedRooms);

  /// Connection status
  bool get isConnected => _isConnected;

  /// User ID for the current connection
  String? get userId => _userId;

  /// Get the socket ID if connected
  String? get socketId => _isConnected ? _socket?.id : null;
}