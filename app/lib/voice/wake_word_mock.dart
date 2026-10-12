import 'dart:async';

import 'wake_word.dart';

/// MOCK: Simulated wake-word detector.
///
/// Never fires on its own — call [simulateWake] to push a detection onto
/// [onWake] on demand (tests, demos, scripted scenarios). [start]/[stop]
/// just flip [isRunning]; no microphone or keyword-spotting runs.
class MockWakeWord implements WakeWordDetector {
  final _wake = StreamController<String>.broadcast();
  bool _running = false;

  @override
  final String keyword;

  /// MOCK: How many detections have been simulated.
  int detectionCount = 0;

  MockWakeWord({this.keyword = 'hey np'});

  @override
  Stream<String> get onWake => _wake.stream;

  @override
  bool get isRunning => _running;

  /// MOCK: Mark the fake spotter as listening.
  @override
  Future<void> start() async {
    _running = true;
  }

  /// MOCK: Mark the fake spotter as stopped.
  @override
  Future<void> stop() async {
    _running = false;
  }

  /// MOCK: Fire a wake-word detection on demand.
  void simulateWake() {
    if (!_running) return;
    detectionCount++;
    _wake.add(keyword);
  }

  /// MOCK: Release the detection stream.
  void dispose() => _wake.close();
}
