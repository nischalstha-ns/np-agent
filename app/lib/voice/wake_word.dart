/// Wake-word detection contract.
///
/// Detects a spoken keyword (e.g. "hey NP") in a continuous audio stream and
/// emits an event per detection. Implementations need a native keyword-spotting
/// engine (e.g. openWakeWord or Porcupine via a platform plugin); this file
/// defines the contract only.
abstract class WakeWordDetector {
  /// The keyword this detector listens for, e.g. 'hey np'.
  String get keyword;

  /// Emits the detected keyword (or a detection timestamp string) each time
  /// the wake word is spotted while [isRunning].
  Stream<String> get onWake;

  bool get isRunning;

  /// Start listening on the microphone.
  Future<void> start();

  /// Stop listening and release the microphone.
  Future<void> stop();
}

/// Test/fallback detector that never fires (useful for wiring without a
/// native engine).
class NullWakeWordDetector implements WakeWordDetector {
  @override
  final String keyword;

  NullWakeWordDetector({this.keyword = 'hey np'});

  @override
  Stream<String> get onWake => const Stream.empty();

  @override
  bool get isRunning => false;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
