class TranscriptUpdate {
  final int sequenceId;
  final String text;
  final bool isPartial;
  final double timestamp;

  TranscriptUpdate({
    required this.sequenceId,
    required this.text,
    required this.isPartial,
    required this.timestamp,
  });

  factory TranscriptUpdate.fromJson(Map<String, dynamic> json) {
    return TranscriptUpdate(
      sequenceId: json['sequence_id'] as int,
      text: json['text'] as String,
      isPartial: json['is_partial'] as bool? ?? true,
      timestamp: (json['timestamp'] as num).toDouble(),
    );
  }
}
