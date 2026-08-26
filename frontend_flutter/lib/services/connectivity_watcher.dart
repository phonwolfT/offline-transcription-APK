import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'sync_manager.dart';

class ConnectivityWatcher extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _subscription;
  bool _isOnline = false;

  bool get isOnline => _isOnline;

  ConnectivityWatcher() {
    _init();
  }

  Future<void> _init() async {
    final results = await _connectivity.checkConnectivity();
    _updateStatus(results);

    _subscription = _connectivity.onConnectivityChanged.listen(_updateStatus);
  }

  void _updateStatus(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;
    // Consider online if any of the results is not 'none'
    _isOnline = results.any((result) => result != ConnectivityResult.none);
    
    notifyListeners();

    if (!wasOnline && _isOnline) {
      // Transitioned from offline to online
      SyncManager.instance.processPendingQueue();
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
