/// REAL: Wake-word detection contract.
///
/// Detects a spoken keyword (e.g. "hey NP") in a continuous audio stream and
/// emits an event per detection. Implementations need a native keyword-spotting
/// engine (e.g. openWakeWord or Porcupine via a platform plugin); this file
/// defines the contract only.
abstract class WakeWordDetector {
  /// REAL: The keyword this detector listens for, e.g. 'hey np'.
  String get keyword;

  /// REAL: Emits the detected keyword (or a detection timestamp string) each time
  /// the wake word is spotted while [isRunning].
  Stream<String> get onWake;

  /// REAL: Whether running.
  bool get isRunning;

  /// REAL: Start listening on the microphone.
  Future<void> start();

  /// REAL: Stop listening and release the microphone.
  Future<void> stop();
}

/// MOCK: Test/fallback detector that never fires (useful for wiring without a
/// native engine).
class NullWakeWordDetector implements WakeWordDetector {
  /// MOCK: The keyword.
  @override
  final String keyword;

  NullWakeWordDetector({this.keyword = 'hey np'});

  /// MOCK: The on wake.
  @override
  Stream<String> get onWake => const Stream.empty();

  /// MOCK: Whether running.
  @override
  bool get isRunning => false;

  /// MOCK: Starts.
  @override
  Future<void> start() async {}

  /// MOCK: Stops.
  @override
  Future<void> stop() async {}
}
