class MovieFile {
  MovieFile({
    required this.id,
    this.path,
    this.container,
    this.videoCodec,
    this.audioCodec,
    this.width,
    this.height,
    this.duration,
    this.bitDepth,
    this.hdr = false,
    this.sizeBytes,
  });

  final int id;
  final String? path;
  final String? container;
  final String? videoCodec;
  final String? audioCodec;
  final int? width;
  final int? height;
  final double? duration;
  final int? bitDepth;
  final bool hdr;
  final int? sizeBytes;

  factory MovieFile.fromJson(Map<String, dynamic> j) => MovieFile(
        id: j['id'] as int,
        path: j['path'] as String?,
        container: j['container'] as String?,
        videoCodec: j['video_codec'] as String?,
        audioCodec: j['audio_codec'] as String?,
        width: j['width'] as int?,
        height: j['height'] as int?,
        duration: (j['duration'] as num?)?.toDouble(),
        bitDepth: j['bit_depth'] as int?,
        hdr: j['hdr'] == true,
        sizeBytes: (j['size_bytes'] as num?)?.toInt(),
      );

  String get filename =>
      path == null ? '—' : path!.split(RegExp(r'[\\/]')).last;

  String get resolution =>
      (width != null && height != null) ? '$width×$height' : '—';

  String get sizeLabel => sizeBytes == null
      ? '—'
      : '${(sizeBytes! / 1073741824).toStringAsFixed(2)} GB';

  String? get durationLabel {
    if (duration == null || duration == 0) return null;
    final total = duration!.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}
