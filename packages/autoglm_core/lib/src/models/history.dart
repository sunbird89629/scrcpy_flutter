/// Represents a single conversation session.
class ConversationRecord {
  /// Creates a new [ConversationRecord].
  const ConversationRecord({
    required this.id,
    required this.deviceId,
    required this.startTime,
    required this.lastUpdated,
    this.taskDescription,
    this.status = 'active',
  });

  /// The unique session ID.
  final String id;

  /// The device ID associated with this session.
  final String deviceId;

  /// The time the session started.
  final DateTime startTime;

  /// The time of the last update.
  final DateTime lastUpdated;

  /// Optional description of the task.
  final String? taskDescription;

  /// Current status (e.g., active, completed, error).
  final String status;

  /// Converts the record to a JSON map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'device_id': deviceId,
    'start_time': startTime.toIso8601String(),
    'last_updated': lastUpdated.toIso8601String(),
    'task_description': taskDescription,
    'status': status,
  };

  /// Creates a record from a JSON map.
  factory ConversationRecord.fromJson(Map<String, dynamic> json) =>
      ConversationRecord(
        id: json['id'] as String,
        deviceId: json['device_id'] as String,
        startTime: DateTime.parse(json['start_time'] as String),
        lastUpdated: DateTime.parse(json['last_updated'] as String),
        taskDescription: json['task_description'] as String?,
        status: json['status'] as String? ?? 'active',
      );
}

/// Represents a single step within a conversation.
class StepRecord {
  /// Creates a new [StepRecord].
  const StepRecord({
    required this.id,
    required this.conversationId,
    required this.stepNumber,
    required this.timestamp,
    required this.action,
    this.observation,
    this.screenshotPath,
  });

  /// The unique step ID.
  final String id;

  /// The ID of the conversation this step belongs to.
  final String conversationId;

  /// The sequence number of this step.
  final int stepNumber;

  /// The time the step occurred.
  final DateTime timestamp;

  /// The action performed in this step.
  final String action;

  /// The observation/result of the action.
  final String? observation;

  /// Path to the screenshot taken for this step.
  final String? screenshotPath;

  /// Converts the record to a JSON map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'conversation_id': conversationId,
    'step_number': stepNumber,
    'timestamp': timestamp.toIso8601String(),
    'action': action,
    'observation': observation,
    'screenshot_path': screenshotPath,
  };

  /// Creates a record from a JSON map.
  factory StepRecord.fromJson(Map<String, dynamic> json) => StepRecord(
    id: json['id'] as String,
    conversationId: json['conversation_id'] as String,
    stepNumber: json['step_number'] as int,
    timestamp: DateTime.parse(json['timestamp'] as String),
    action: json['action'] as String,
    observation: json['observation'] as String?,
    screenshotPath: json['screenshot_path'] as String?,
  );
}
