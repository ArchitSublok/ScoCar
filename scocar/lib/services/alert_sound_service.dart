import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AlertSoundService
//
// Plays a repeating beep alert for exactly 60 seconds when a new gate
// approval request arrives on the Resident Dashboard.
//
// Usage:
//   await AlertSoundService().startAlert();   // begin beeping
//   AlertSoundService().stopAlert();           // stop immediately
//
// The service auto-stops after 60 seconds even if stopAlert() is not called.
// ─────────────────────────────────────────────────────────────────────────────
class AlertSoundService {
  static final AlertSoundService _instance = AlertSoundService._internal();
  factory AlertSoundService() => _instance;
  AlertSoundService._internal();

  final AudioPlayer _player  = AudioPlayer();
  Timer?            _autoStopTimer;
  Timer?            _beepTimer;
  bool              _isPlaying = false;

  static const int _alertDurationSeconds = 60;
  static const int _beepIntervalSeconds  = 2; // beep every 2 seconds

  /// Start the 60-second repeating alert beep.
  /// Safe to call multiple times — only one alert runs at a time.
  Future<void> startAlert() async {
    if (_isPlaying) return; // already alerting
    _isPlaying = true;

    try {
      // Play the built-in notification sound using AudioPlayer
      // Uses a short beep URL that works without any asset file
      await _playBeep();

      // Repeat beep every 2 seconds
      _beepTimer = Timer.periodic(
        const Duration(seconds: _beepIntervalSeconds),
        (_) => _playBeep(),
      );

      // Auto-stop after 60 seconds no matter what
      _autoStopTimer = Timer(
        const Duration(seconds: _alertDurationSeconds),
        stopAlert,
      );
    } catch (e) {
      debugPrint('AlertSoundService: audio error: $e');
      _isPlaying = false;
    }
  }

  /// Stop the alert immediately (called when resident taps Approve/Deny).
  void stopAlert() {
    _beepTimer?.cancel();
    _autoStopTimer?.cancel();
    _player.stop();
    _isPlaying = false;
  }

  bool get isPlaying => _isPlaying;

  Future<void> _playBeep() async {
    try {
      // Short notification beep — hosted CDN, no asset file needed
      await _player.play(
        UrlSource(
          'https://www.soundjay.com/buttons/sounds/beep-01a.mp3',
        ),
        volume: 1.0,
      );
    } catch (e) {
      // Silently ignore playback errors — alert still works via UI
      debugPrint('AlertSoundService: beep error: $e');
    }
  }

  void dispose() {
    stopAlert();
    _player.dispose();
  }
}
