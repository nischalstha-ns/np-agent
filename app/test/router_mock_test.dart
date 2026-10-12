// Tests for MockStreamingProvider and LlmRouter fallback behavior.
// The router is built with no online provider and an offline provider whose
// search dirs do not exist, so it must deterministically fall back to the
// mock provider — no network, no GGUF files, fully hermetic.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:np/llm/llm_provider.dart';
import 'package:np/llm/mock_provider.dart';
import 'package:np/llm/offline_provider.dart';
import 'package:np/llm/router.dart';

void main() {
  group('MockStreamingProvider', () {
    test('greeting reply', () async {
      final p = MockStreamingProvider(seed: 1);
      final reply = await p.generate('hi there');
      expect(reply, startsWith('Hello! I am NP'));
      await p.dispose();
    });

    test('farewell reply', () async {
      final p = MockStreamingProvider(seed: 1);
      expect(await p.generate('bye!'), contains('Goodbye!'));
      await p.dispose();
    });

    test('identity reply', () async {
      final p = MockStreamingProvider(seed: 1);
      final reply = await p.generate('who are you?');
      expect(reply, contains('NP'));
      await p.dispose();
    });

    test('help reply lists capabilities', () async {
      final p = MockStreamingProvider(seed: 1);
      final reply = await p.generate('what can you do?');
      expect(reply, contains('files'));
      await p.dispose();
    });

    test('thanks reply', () async {
      final p = MockStreamingProvider(seed: 1);
      expect(await p.generate('thank you'), contains('You are welcome'));
      await p.dispose();
    });

    test('unknown prompt gets the generic mock reply', () async {
      final p = MockStreamingProvider(seed: 1);
      final reply = await p.generate('explain quantum tunneling');
      expect(reply, contains('mock language model'));
      await p.dispose();
    });

    test('streams tokens in order; joined tokens equal the full reply',
        () async {
      final p = MockStreamingProvider(seed: 42);
      final full = await p.generate('thank you');

      final tokens = <String>[];
      await p.generateStreaming('thank you', tokens.add);

      expect(tokens, isNotEmpty);
      // Every token is a single word (space-prefixed except the first).
      for (final t in tokens) {
        expect(t.trim().split(' ').length, 1);
      }
      expect(tokens.join(), full);
      expect(tokens.length, full.split(' ').length);
      await p.dispose();
    });
  });

  group('LlmRouter fallback', () {
    late LlmRouter router;

    setUp(() async {
      final dir = await Directory.systemTemp.createTemp('np-gguf-empty-');
      addTearDown(() => dir.delete(recursive: true));
      router = LlmRouter(
        offline: OfflineLlmProvider(searchDirs: [dir.path]),
        online: null, // no API key configured
        mock: MockStreamingProvider(seed: 7),
      );
    });

    tearDown(() async {
      await router.dispose();
    });

    test('falls back to the mock provider with no GGUF and no online',
        () async {
      final selected = await router.selectProvider();
      expect(selected, isA<MockStreamingProvider>());
      expect(selected.name, 'mock-streaming');
    });

    test('generate routes to the mock and answers', () async {
      final reply = await router.generate('hello');
      expect(reply, startsWith('Hello! I am NP'));
    });

    test('generateStreaming collects ordered non-empty tokens', () async {
      final tokens = <String>[];
      await router.generateStreaming(
          'thank you', tokens.add,
          options: const LlmOptions(maxTokens: 50));
      expect(tokens, isNotEmpty);
      final joined = tokens.join();
      expect(joined, contains('You are welcome'));
    });

    test('routingDecision explains the mock fallback', () async {
      final decision = await router.routingDecision();
      expect(decision, startsWith('mock'));
    });

    test('checkOnlineConnectivity returns a bool without throwing', () async {
      final online = await router.checkOnlineConnectivity(
          timeout: const Duration(seconds: 2));
      expect(online, isA<bool>());
    }, timeout: const Timeout(Duration(seconds: 15)));
  });

  group('OfflineLlmProvider model discovery', () {
    test('empty dirs yield no models and parseQuant handles filenames', () async {
      final dir = await Directory.systemTemp.createTemp('np-gguf-scan-');
      addTearDown(() => dir.delete(recursive: true));
      final provider = OfflineLlmProvider(searchDirs: [dir.path]);

      expect(await provider.discoverModels(), isEmpty);
      expect(provider.hasModelLoaded, isFalse);
      expect(provider.currentModel, isNull);

      // A real .gguf file on disk is discovered.
      final modelFile = File(
          '${dir.path}/llama-3-8b-Q4_K_M.gguf');
      await modelFile.writeAsBytes([1, 2, 3]);
      final found = await provider.discoverModels();
      expect(found.length, 1);
      expect(found.first.fileName, 'llama-3-8b-Q4_K_M.gguf');
      expect(
          OfflineLlmProvider.parseQuantFromFilename('llama-3-8b-Q4_K_M.gguf'),
          'Q4_K_M');
      expect(OfflineLlmProvider.parseQuantFromFilename('model.gguf'), isNull);
      await provider.dispose();
    });
  });
}
