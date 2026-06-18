enum SopPolarity { positive, negative }

/// One task-level operation experience for a given app package.
class SopRecord {
  const SopRecord({
    required this.id,
    required this.package,
    required this.intent,
    required this.polarity,
    required this.steps,
    required this.sourceTask,
    required this.createdAt,
    this.pitfall,
    this.deviceHint,
  });

  final String id;
  final String package;
  final String intent;
  final SopPolarity polarity;
  final List<String> steps;
  final String sourceTask;
  final DateTime createdAt;
  final String? pitfall;
  final String? deviceHint;

  Map<String, dynamic> toJson() => {
    'id': id,
    'package': package,
    'intent': intent,
    'polarity': polarity.name,
    'steps': steps,
    'source_task': sourceTask,
    'created_at': createdAt.toIso8601String(),
    if (pitfall != null) 'pitfall': pitfall,
    if (deviceHint != null) 'device_hint': deviceHint,
  };

  factory SopRecord.fromJson(Map<String, dynamic> j) => SopRecord(
    id: j['id'] as String,
    package: j['package'] as String,
    intent: j['intent'] as String,
    polarity: SopPolarity.values.byName(j['polarity'] as String),
    steps: (j['steps'] as List).cast<String>(),
    sourceTask: j['source_task'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    pitfall: j['pitfall'] as String?,
    deviceHint: j['device_hint'] as String?,
  );
}
