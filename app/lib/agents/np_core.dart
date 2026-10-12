import 'dart:io';

import '../control/desktop_control.dart';
import '../control/mock_desktop.dart';
import '../core/config.dart';
import '../core/di.dart';
import '../llm/llm_provider.dart';
import '../llm/offline_provider.dart';
import '../llm/online_provider.dart';
import '../llm/router.dart';
import '../memory/embeddings.dart';
import '../memory/in_memory_store.dart';
import '../memory/long_term.dart';
import '../memory/memory_store.dart';
import '../memory/project_memory.dart';
import '../memory/retrieval.dart';
import '../memory/semantic.dart';
import '../memory/short_term.dart';
import '../memory/skill_memory.dart';
import '../memory/tool_usage.dart';
import '../memory/user_profile.dart';
import '../native/channels.dart';
import '../native/mock_channels.dart';
import '../tools/browser_tool.dart';
import '../tools/code_tool.dart';
import '../tools/file_tool.dart';
import '../tools/media_tools.dart';
import '../tools/memory_tool.dart';
import '../tools/productivity_tools.dart';
import '../tools/terminal_tool.dart';
import '../tools/tool_registry.dart';
import '../vision/ocr_mock.dart';
import '../vision/screen_mock.dart';
import '../voice/stt.dart';
import '../voice/stt_mock.dart';
import '../voice/tts_mock.dart';
import '../voice/wake_word.dart';
import '../voice/wake_word_mock.dart';
import 'agent.dart';
import 'automation_agent.dart';
import 'learning_agent.dart';
import 'memory_agent.dart';
import 'pipeline.dart';
import 'planner_agent.dart';
import 'reasoning_agent.dart';
import 'safety_agent.dart';
import 'speech_agent.dart';
import 'tool_agent.dart';
import 'verification_agent.dart';
import 'vision_agent.dart';

/// REAL: NP Core — builds the DI container, wires every agent/tool/memory/
/// LLM, and exposes the single entry point [handle].
///
/// ```dart
/// final core = await NpCore.initialize(); // mocks wired by default
/// final reply = await core.handle('list files in /tmp');
/// await core.dispose();
/// ```
///
/// [useMocks] (default true): wire the mock native layer — [MockStt],
/// [MockTts], [MockWakeWord], [MockOcr], [MockScreenUnderstanding],
/// [MockDesktopControl] and the mock method-channel engines — and use the
/// pure-Dart [InMemoryMemoryStore] instead of sqflite. Pass
/// `useMocks: false` on a real device build with native plugins linked.
class NpCore {
  /// REAL: The service-locator DI container for this core instance.
  final ServiceLocator di = ServiceLocator();

  /// REAL: The 9-stage agent pipeline.
  late final Pipeline pipeline;

  /// REAL: The LLM router (offline GGUF -> online -> mock fallback).
  late final LlmRouter llm;

  /// REAL: The memory store (sqflite or in-memory, per [useMocks]).
  late final MemoryStore store;

  NpCore._();

  /// REAL: Build and wire the whole system.
  ///
  /// [autoApprove] auto-approves `needsApproval` safety decisions (tests /
  /// trusted local runs). [useMocks] wires the mock native layer and the
  /// in-memory store (default true). Prints progress; never throws for
  /// optional subsystems (model discovery is best-effort).
  static Future<NpCore> initialize(
      {bool autoApprove = false, bool useMocks = true}) async {
    /// REAL: The core.
    final core = NpCore._();
    /// REAL: The di.
    final di = core.di;

    // --- memory ------------------------------------------------------------
    /// REAL: Stores.
    final MemoryStore store =
        useMocks ? InMemoryMemoryStore() : await MemoryStore.open();
    core.store = store;
    di.register<MemoryStore>(store);

    /// REAL: The embeddings.
    final embeddings = HashingEmbedding(dimension: AppConfig.embeddingDim);
    di.register<EmbeddingProvider>(embeddings);

    /// REAL: The retrieval.
    final retrieval =
        RetrievalService(store: store, embeddings: embeddings);
    di.register<RetrievalService>(retrieval);
    di.register<ShortTermMemory>(ShortTermMemory(store, embeddings));
    di.register<LongTermMemory>(LongTermMemory(store, embeddings));
    di.register<SemanticMemory>(SemanticMemory(store, embeddings));
    di.register<UserProfileMemory>(UserProfileMemory(store));
    di.register<ToolUsageMemory>(ToolUsageMemory(store));
    di.register<ProjectMemory>(ProjectMemory(store));
    di.register<SkillMemory>(SkillMemory(store));

    // --- tools --------------------------------------------------------------
    /// REAL: The registry.
    final registry = ToolRegistry();
    // Real local tools:
    registry.register(FileTool());
    registry.register(TerminalTool());
    registry.register(BrowserTool());
    registry.register(CodeTool());
    /// REAL: The media engine.
    final MediaEngineChannel? mediaEngine =
        useMocks ? MockMediaEngine() : null;
    registry.register(ImageTool(engine: mediaEngine));
    registry.register(VideoTool(engine: mediaEngine));
    registry.register(AudioTool(engine: mediaEngine));
    registry.register(CalendarTool());
    registry.register(EmailTool());
    registry.register(TaskTool(store: store));
    registry.register(PdfTool());
    registry.register(DocumentTool());
    registry.register(DatabaseTool(store: store));
    registry.register(MemoryTool(store: store));
    registry.register(ResearchTool());
    // AutomationTool is registered after the automation agent is built.
    di.register<ToolRegistry>(registry);

    // --- native layer (mocks by default) --------------------------------------
    /// REAL: The stt.
    final SpeechToText? stt = useMocks ? MockStt() : null;
    /// MOCK: The mock tts.
    final MockTts? mockTts = useMocks ? MockTts() : null;
    /// REAL: The wake word.
    final WakeWordDetector? wakeWord = useMocks ? MockWakeWord() : null;
    if (useMocks) {
      di.register<MicrophoneChannel>(MockMicrophoneChannel());
      di.register<SttEngineChannel>(MockSttEngineChannel());
      di.register<TtsEngineChannel>(MockTtsEngineChannel());
      di.register<WakeWordEngineChannel>(MockWakeWordEngineChannel());
      di.register<WakeWordDetector>(wakeWord!);
      di.register<SpeechToText>(stt!);
      di.register<MockTts>(mockTts!);
      di.register<LlamaEngineChannel>(MockLlamaEngineChannel());
      di.register<OsControlChannel>(
          MockOsControlChannel(platformName: Platform.operatingSystem));
      di.register<DesktopControl>(MockDesktopControl.forCurrentOs());
    }

    // --- agents ---------------------------------------------------------------
    /// REAL: The safety.
    final safety = SafetyAgent(registry);
    /// REAL: The planner.
    final planner = PlannerAgent();
    /// REAL: The reasoning.
    final reasoning = ReasoningAgent();
    /// REAL: The memory agent.
    final memoryAgent = MemoryAgent(
      retrieval: retrieval,
      shortTerm: di.get<ShortTermMemory>(),
    );
    /// REAL: The tool agent.
    final toolAgent = ToolAgent(
      registry: registry,
      safety: safety,
      usage: di.get<ToolUsageMemory>(),
    );
    /// REAL: The verification.
    final verification = VerificationAgent();
    /// REAL: The learning.
    final learning = LearningAgent(store: store);
    /// REAL: The vision.
    final vision = VisionAgent(
      ocr: useMocks ? MockOcr() : null,
      screen: useMocks ? MockScreenUnderstanding() : null,
    );
    /// REAL: The speech.
    final speech = SpeechAgent(
      stt: stt,
      tts: mockTts,
      controller: SpeechController(),
    );
    /// REAL: The automation.
    final automation =
        AutomationAgent(registry: registry, safety: safety);
    registry.register(AutomationTool(agent: automation));

    di.register<SafetyAgent>(safety);
    di.register<PlannerAgent>(planner);
    di.register<ReasoningAgent>(reasoning);
    di.register<MemoryAgent>(memoryAgent);
    di.register<ToolAgent>(toolAgent);
    di.register<VerificationAgent>(verification);
    di.register<LearningAgent>(learning);
    di.register<VisionAgent>(vision);
    di.register<SpeechAgent>(speech);
    di.register<AutomationAgent>(automation);
    di.register<List<Agent>>([
      planner,
      reasoning,
      memoryAgent,
      safety,
      toolAgent,
      verification,
      vision,
      speech,
      learning,
      automation,
    ]);

    // --- pipeline -------------------------------------------------------------
    core.pipeline = Pipeline(
      store: store,
      planner: planner,
      reasoning: reasoning,
      memory: memoryAgent,
      tools: toolAgent,
      verification: verification,
      learning: learning,
      autoApprove: autoApprove,
    );
    di.register<Pipeline>(core.pipeline);

    // --- LLM --------------------------------------------------------------------
    /// REAL: The offline.
    final offline = OfflineLlmProvider();
    /// REAL: The online.
    final online = OpenAICompatibleProvider(
      apiKey: Platform.environment['NP_API_KEY'],
      baseUrl:
          Platform.environment['NP_API_BASE'] ?? 'https://api.openai.com/v1',
      model: Platform.environment['NP_MODEL'] ?? 'gpt-4o-mini',
    );
    core.llm = LlmRouter(offline: offline, online: online);
    di.register<LlmProvider>(core.llm);
    di.register<LlmRouter>(core.llm);
    di.register<OfflineLlmProvider>(offline);

    // --- best-effort model discovery ---------------------------------------------
    try {
      /// REAL: The models.
      final models = await offline.discoverModels();
      if (models.isNotEmpty) {
        await offline.loadModel(models.first);
      }
    } catch (_) {
      // Offline inference is optional; the router falls back to online/mock.
    }

    return core;
  }

  /// REAL: Handle one user input through the full pipeline; returns the
  /// reply text.
  Future<String> handle(String input, {String sessionId = 'default'}) async {
    /// REAL: The result.
    final result = await pipeline.run(input, sessionId: sessionId);
    return result.response;
  }

  /// REAL: Full pipeline result (stages, timings) for dashboards/debugging.
  Future<PipelineResult> runDetailed(String input,
      {String sessionId = 'default'}) {
    return pipeline.run(input, sessionId: sessionId);
  }

  /// REAL: Release LLM resources, close the store, and reset the DI
  /// container.
  Future<void> dispose() async {
    try {
      await llm.dispose();
    } catch (_) {}
    try {
      await store.close();
    } catch (_) {}
    di.reset();
  }
}
