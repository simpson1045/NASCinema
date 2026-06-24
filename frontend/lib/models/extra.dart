class Extra {
  Extra({
    required this.id,
    required this.title,
    required this.type,
    this.resolution,
    this.duration,
    this.sizeBytes,
  });

  final int id;
  final String title;
  final String type;
  final String? resolution;
  final double? duration;
  final int? sizeBytes;

  factory Extra.fromJson(Map<String, dynamic> j) => Extra(
        id: j['id'] as int,
        title: (j['title'] ?? 'Untitled').toString(),
        type: (j['type'] ?? 'Extra').toString(),
        resolution: j['resolution'] as String?,
        duration: (j['duration'] as num?)?.toDouble(),
        sizeBytes: (j['size_bytes'] as num?)?.toInt(),
      );

  String? get durationLabel {
    if (duration == null || duration == 0) return null;
    final total = duration!.round();
    if (total < 60) return '${total}s';
    final m = total ~/ 60;
    final h = m ~/ 60;
    return h > 0 ? '${h}h ${m % 60}m' : '${m}m';
  }
}
