/// REAL: Base types for every NP agent.
///
/// An [Agent] is a named, describable unit of work that consumes a
/// [TaskContext] and produces an [AgentResult]. The [pipeline] chains agents
/// together; each agent owns exactly one stage of reasoning.
class ChatMessage {
  /// REAL: The role.
  final String role; // 'user' | 'assistant' | 'system'
  /// REAL: The content.
  final String content;

  const ChatMessage(this.role, this.content);

  Map<String, String> toJson() => {'role': role, 'content': content};

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        json['role'] as String? ?? 'user',
        json['content'] as String? ?? '',
      );
}

/// REAL: Everything an agent needs to know about the current unit of work.
class TaskContext {
  /// REAL: The task id.
  final String taskId;
  /// REAL: The input.
  final String input;
  /// REAL: The session id.
  final String sessionId;
  /// REAL: The history.
  final List<ChatMessage> history;
  /// REAL: The metadata.
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

/// REAL: The outcome of a single agent execution.
class AgentResult {
  /// REAL: The agent name.
  final String agentName;
  /// REAL: The success.
  final bool success;
  /// REAL: The output.
  final Map<String, dynamic> output;
  /// REAL: The error.
  final String? error;
  /// REAL: The started at.
  final DateTime startedAt;
  /// REAL: The finished at.
  final DateTime finishedAt;

  const AgentResult({
    required this.agentName,
    required this.success,
    this.output = const {},
    this.error,
    required this.startedAt,
    required this.finishedAt,
  });

  /// REAL: The duration ms.
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

/// REAL: Base class for all NP agents.
abstract class Agent {
  /// REAL: Stable machine name, e.g. 'planner'.
  String get name;

  /// REAL: One-line human description of what this agent does.
  String describe();

  /// REAL: Run the agent against [ctx]. Implementations must never throw for
  /// expected failures — return `AgentResult.fail(...)` instead.
  Future<AgentResult> execute(TaskContext ctx);
}
