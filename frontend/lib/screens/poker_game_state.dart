import 'dart:async';

/// Holds state information for the poker game screen
class PokerGameState {
  // Enhanced state management
  Timer? refreshTimer;
  Timer? uiUpdateTimer;
  int lastKnownPlayerIndex = -1;
  bool forcedRefreshInProgress = false;
  int consecutiveErrors = 0;
  DateTime? lastSuccessfulUpdate;

  // Set of displayedNotifications to avoid duplicates
  final Set<String> displayedNotifications = {};
  bool isShowingNotification = false;

  /// Setup a timer to update the UI regularly
  void setupUiUpdateTimer(Function updateUI) {
    uiUpdateTimer?.cancel();

    // Update UI every 500ms to ensure smoothness
    uiUpdateTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      updateUI();
    });
  }

  /// Setup a timer to force refresh of game state periodically
  void setupForcedRefreshTimer(String authToken, Function(String) refreshFunction) {
    refreshTimer?.cancel();

    // Force refresh every 5 seconds
    refreshTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (!forcedRefreshInProgress) {
        // Check if it's been too long since last successful update
        bool needsRefresh = true;

        if (lastSuccessfulUpdate != null) {
          final timeSinceUpdate = DateTime.now().difference(lastSuccessfulUpdate!);

          // If recently updated successfully, may not need refresh
          if (timeSinceUpdate.inSeconds < 3) {
            needsRefresh = false;
          }
        }

        if (needsRefresh) {
          refreshFunction(authToken);
        }
      }
    });
  }

  /// Check if notification should be shown
  bool shouldShowNotification(String notificationId) {
    // Don't show duplicate notifications within a short timeframe
    if (displayedNotifications.contains(notificationId)) {
      return false;
    }

    // Don't show if another notification is currently showing
    if (isShowingNotification) {
      return false;
    }

    return true;
  }

  /// Mark notification as shown
  void markNotificationShown(String notificationId) {
    isShowingNotification = true;
    displayedNotifications.add(notificationId);

    // After 3 seconds, remove this notification ID from the set
    Timer(Duration(seconds: 3), () {
      displayedNotifications.remove(notificationId);
    });

    // After 1 second, allow new notifications
    Timer(Duration(seconds: 1), () {
      isShowingNotification = false;
    });
  }

  /// Clean up resources
  void dispose() {
    refreshTimer?.cancel();
    uiUpdateTimer?.cancel();
  }
}