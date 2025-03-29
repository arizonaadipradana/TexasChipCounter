import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/api_config.dart';

/// A singleton manager for socket.io connections to ensure
/// persistent connections across screen transitions.
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

  // Track event listeners to avoid duplicates
  final Map<String, Set<Function(dynamic)>> _eventListeners = {};

  // Track rooms the socket has joined
  final Set<String> _joinedRooms = {};

  /// Initialize the socket connection if not already connected
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
    }

    // Create new socket
    _socket = io.io(ApiConfig.baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'extraHeaders': {'Authorization': 'Bearer $_authToken'}
    });

    // Connect and set up event handlers
    _socket!.connect();

    _socket!.onConnect((_) {
      print('Socket connected with ID: ${_socket!.id}');
      _isConnected = true;

      // Authenticate the socket connection
      _socket!.emit('authenticate', {'token': _authToken});

      // Rejoin any rooms that were previously joined
      for (final roomId in _joinedRooms) {
        print('Rejoining room: $roomId');
        _socket!.emit('join_game', roomId);
      }
    });

    _socket!.onDisconnect((_) {
      print('Socket disconnected');
      _isConnected = false;
    });

    _socket!.onError((error) {
      print('Socket error: $error');
    });

    _socket!.onConnectError((error) {
      print('Socket connection error: $error');

      // Try to reconnect after a short delay
      Future.delayed(Duration(seconds: 2), () {
        if (!_isConnected && _socket != null) {
          print('Attempting to reconnect socket...');
          _socket!.connect();
        }
      });
    });

    // Set up reconnection handlers
    _socket!.on('reconnect', (_) {
      print('Socket reconnected');

      // Re-authenticate
      _socket!.emit('authenticate', {'token': _authToken});

      // Rejoin all rooms
      for (final roomId in _joinedRooms) {
        print('Rejoining room after reconnect: $roomId');
        _socket!.emit('join_game', roomId);
      }
    });
  }

  /// Join a game room and track it
  void joinGameRoom(String gameId) {
    if (_socket == null || !_isConnected) {
      print('Socket not connected, cannot join room: $gameId');

      // Store the room ID to join later when connected
      _joinedRooms.add(gameId);

      // Try to connect if socket exists
      if (_socket != null && !_isConnected) {
        print('Attempting to connect socket to join room: $gameId');
        _socket!.connect();
      }

      return;
    }

    print('Joining game room: $gameId');
    _socket!.emit('join_game', gameId);
    _joinedRooms.add(gameId);
  }

  /// Leave a game room and remove from tracking
  void leaveGameRoom(String gameId) {
    if (_socket == null) return;

    print('Leaving game room: $gameId');
    _socket!.emit('leave_game', gameId);
    _joinedRooms.remove(gameId);
  }

  /// Emit an event to the server
  void emit(String event, dynamic data) {
    if (_socket == null || !_isConnected) {
      print('Socket not connected, cannot emit event: $event');

      // Try to connect if socket exists but not connected
      if (_socket != null && !_isConnected) {
        print('Attempting to connect socket to emit event: $event');
        _socket!.connect();

        // Queue the emit for after connection (basic retry)
        Future.delayed(Duration(milliseconds: 500), () {
          if (_isConnected) {
            print('Socket connected, emitting delayed event: $event');
            _socket!.emit(event, data);
          } else {
            print('Socket still not connected, could not emit event: $event');
          }
        });
      }

      return;
    }

    _socket!.emit(event, data);
  }

  /// Add event listener with tracking to prevent duplicates
  void on(String event, Function(dynamic) handler) {
    if (_socket == null) return;

    // Add to our tracking map
    if (!_eventListeners.containsKey(event)) {
      _eventListeners[event] = {};
    }

    // Check if this handler is already registered
    if (_eventListeners[event]!.contains(handler)) {
      print('Handler already registered for event: $event, skipping');
      return;
    }

    _eventListeners[event]!.add(handler);

    // Add to actual socket
    _socket!.on(event, handler);
    print('Added listener for event: $event');
  }

  /// Remove specific event listener
  void off(String event, Function(dynamic) handler) {
    if (_socket == null) return;

    // Remove from our tracking
    if (_eventListeners.containsKey(event)) {
      _eventListeners[event]!.remove(handler);
    }

    // Remove from socket
    _socket!.off(event, handler);
    print('Removed listener for event: $event');
  }

  /// Clear all listeners for an event
  void clearListeners(String event) {
    if (_socket == null) return;

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
      print('Socket manager disconnected and reset');
    }
  }

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
}