import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repositories/splash_repository.dart';

class SplashViewModel extends ChangeNotifier {
  SplashViewModel({
    required SplashRepository repository,
    // The splash exists to cover startup work, not to be a timed screen. The
    // previous 3s (plus the repository's own delay) was dead time the user
    // read as the app being slow to open; this is just long enough for the
    // intro animation to land.
    Duration navigationDelay = const Duration(milliseconds: 900),
  })  : _repository = repository,
        _navigationDelay = navigationDelay;

  final SplashRepository _repository;
  final Duration _navigationDelay;

  bool _shouldNavigate = false;
  bool get shouldNavigate => _shouldNavigate;

  Future<void> initialize() async {
    _hideSystemUI();
    // Run the preload alongside the animation window instead of after it, so
    // the splash lasts as long as the slower of the two rather than their sum.
    await Future.wait(<Future<void>>[
      _repository.preloadApp(),
      Future<void>.delayed(_navigationDelay),
    ]);
    _showSystemUI();
    _shouldNavigate = true;
    notifyListeners();
  }

  void markNavigationHandled() {
    if (_shouldNavigate) {
      _shouldNavigate = false;
      notifyListeners();
    }
  }

  void _hideSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: <SystemUiOverlay>[],
    );
  }

  void _showSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
  }

  @override
  void dispose() {
    _showSystemUI();
    super.dispose();
  }
}

