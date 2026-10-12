/// Base types for every NP agent.
///
/// An [Agent] is a named, describable unit of work that consumes a
/// [TaskContext] and produces an [AgentResult]. The [pipeline] chains agents
/// together; each agent owns exactly one stage of reasoning.
class ChatMessage {
  final String role; // 'user' | 'assistant' | 'system'
  final String content;

  const ChatMessage(this.role, this.content);

  Map<String, String> toJson() => {'role': role, 'content': content};

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        json['role'] as String? ?? 'user',
        json['content'] as String? ?? '',
      );
}

/// Everything an agent needs to know about the current unit of work.
class TaskContext {
  final String taskId;
  final String input;
  final String sessionId;
  final List<ChatMessage> history;
  final Map<String, dynamic> metadata;

  const TaskContext({
    required this.taskId,
    required this.input,
    this.sessionId = 'default',
    this.history = const [],
    this.metadata = const {},
  });

  TaskContext copyWith({
    List<ChatMessage>? history,
    Map<String, dynamic>? metadata,
  }) =>
      TaskContext(
        taskId: taskId,
        input: input,
        sessionId: sessionId,
        history: history ?? this.history,
        metadata: metadata ?? this.metadata,
      );
}

/// The outcome of a single agent execution.
class AgentResult {
  final String agentName;
  final bool success;
  final Map<String, dynamic> output;
  final String? error;
  final DateTime startedAt;
  final DateTime finishedAt;

  const AgentResult({
    required this.agentName,
    required this.success,
    this.output = const {},
    this.error,
    required this.startedAt,
    required this.finishedAt,
  });

  int get durationMs => finishedAt.difference(startedAt).inMilliseconds;

  factory AgentResult.ok(
    String agentName,
    Map<String, dynamic> output,
    DateTime started,
    DateTime finished,
  ) =>
      AgentResult(
        agentName: agentName,
        success: true,
        output: output,
        startedAt: started,
        finishedAt: finished,
      );

  factory AgentResult.fail(
    String agentName,
    String error,
    DateTime started,
    DateTime finished,
  ) =>
      AgentResult(
        agentName: agentName,
        success: false,
        error: error,
        startedAt: started,
        finishedAt: finished,
      );

  Map<String, dynamic> toJson() => {
        'agent': agentName,
        'success': success,
        'output': output,
        if (error != null) 'error': error,
        'durationMs': durationMs,
      };
}

/// Base class for all NP agents.
abstract class Agent {
  /// Stable machine name, e.g. 'planner'.
  String get name;

  /// One-line human description of what this agent does.
  String describe();

  /// Run the agent against [ctx]. Implementations must never throw for
  /// expected failures — return `AgentResult.fail(...)` instead.
  Future<AgentResult> execute(TaskContext ctx);
}
