import 'dart:io';

import '../core/config.dart';
import '../core/di.dart';
import '../llm/llm_provider.dart';
import '../llm/offline_provider.dart';
import '../llm/online_provider.dart';
import '../llm/router.dart';
import '../memory/embeddings.dart';
import '../memory/long_term.dart';
import '../memory/memory_store.dart';
import '../memory/project_memory.dart';
import '../memory/retrieval.dart';
import '../memory/semantic.dart';
import '../memory/short_term.dart';
import '../memory/skill_memory.dart';
import '../memory/tool_usage.dart';
import '../memory/user_profile.dart';
import '../tools/browser_tool.dart';
import '../tools/code_tool.dart';
import '../tools/file_tool.dart';
import '../tools/media_tools.dart';
import '../tools/productivity_tools.dart';
import '../tools/terminal_tool.dart';
import '../tools/tool_registry.dart';
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

/// NP Core: builds the DI container, wires every agent/tool/memory/LLM, and
/// exposes the single entry point [handle].
///
/// ```dart
/// final core = await NpCore.initialize();
/// final reply = await core.handle('list files in /tmp');
/// await core.dispose();
/// ```
class NpCore {
  final ServiceLocator di = ServiceLocator();

  late final Pipeline pipeline;
  late final LlmRouter llm;
  late final MemoryStore store;

  NpCore._();

  /// Build and wire the whole system. Prints progress; never throws for
  /// optional subsystems (model discovery is best-effort).
  static Future<NpCore> initialize({bool autoApprove = false}) async {
    final core = NpCore._();
    final di = core.di;

    // --- memory ------------------------------------------------------------
    final store = await MemoryStore.open();
    core.store = store;
    di.register<MemoryStore>(store);

    final embeddings = HashingEmbedding(dimension: AppConfig.embeddingDim);
    di.register<EmbeddingProvider>(embeddings);

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
    final registry = ToolRegistry();
    // Real local tools:
    registry.register(FileTool());
    registry.register(TerminalTool());
    registry.register(BrowserTool());
    registry.register(CodeTool());
    // Interface-consistent stubs (need native engines / accounts):
    registry.register(ImageTool());
    registry.register(VideoTool());
    registry.register(AudioTool());
    registry.register(CalendarTool());
    registry.register(EmailTool());
    registry.register(TaskTool());
    registry.register(PdfTool());
    registry.register(DocumentTool());
    registry.register(DatabaseTool());
    registry.register(AutomationTool());
    registry.register(ResearchTool());
    di.register<ToolRegistry>(registry);

    // --- agents ---------------------------------------------------------------
    final safety = SafetyAgent(registry);
    final planner = PlannerAgent();
    final reasoning = ReasoningAgent();
    final memoryAgent = MemoryAgent(
      retrieval: retrieval,
      shortTerm: di.get<ShortTermMemory>(),
    );
    final toolAgent = ToolAgent(
      registry: registry,
      safety: safety,
      usage: di.get<ToolUsageMemory>(),
    );
    final verification = VerificationAgent();
    final learning = LearningAgent(store: store);
    final vision = VisionAgent(); // engines attached later via plugins
    final speech = SpeechAgent(); // engines attached later via plugins
    final automation =
        AutomationAgent(registry: registry, safety: safety);

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
    final offline = OfflineLlmProvider();
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
      final models = await offline.discoverModels();
      if (models.isNotEmpty) {
        await offline.loadModel(models.first);
      }
    } catch (_) {
      // Offline inference is optional; the router falls back to online.
    }

    return core;
  }

  /// Handle one user input through the full pipeline; returns the reply text.
  Future<String> handle(String input, {String sessionId = 'default'}) async {
    final result = await pipeline.run(input, sessionId: sessionId);
    return result.response;
  }

  /// Full pipeline result (stages, timings) for dashboards/debugging.
  Future<PipelineResult> runDetailed(String input,
      {String sessionId = 'default'}) {
    return pipeline.run(input, sessionId: sessionId);
  }

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
