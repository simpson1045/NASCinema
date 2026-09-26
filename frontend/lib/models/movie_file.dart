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
    this.label,
    this.quality,
    this.audioTracks = const [],
    this.subtitleTracks = const [],
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
  // Version name for the pickers ("4K77", "Harmy Despecialized", else a
  // quality summary) and that summary on its own.
  final String? label;
  final String? quality;
  final List<MediaTrack> audioTracks;
  final List<MediaTrack> subtitleTracks;

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
        label: j['label'] as String?,
        quality: j['quality'] as String?,
        audioTracks: MediaTrack.list(j['audio_tracks']),
        subtitleTracks: MediaTrack.list(j['subtitle_tracks']),
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

/// One audio or subtitle track of a version. [id] is mpv's 1-based number
/// within its type (what --aid / --sid take).
class MediaTrack {
  const MediaTrack({
    required this.id,
    required this.title,
    this.desc = '',
    this.language,
    this.lossless = false,
    this.commentary = false,
    this.isDefault = false,
    this.forced = false,
  });

  final int id;
  final String title; // the track's own name, e.g. "1.0 DTS-HD-MA (1977 35mm mono mix)"
  final String desc; // "English · DTS-HD MA · Mono"
  final String? language;
  final bool lossless;
  final bool commentary;
  final bool isDefault;
  final bool forced;

  factory MediaTrack.fromJson(Map<String, dynamic> j) => MediaTrack(
        id: (j['id'] as num).toInt(),
        title: (j['title'] ?? '').toString(),
        desc: (j['desc'] ?? '').toString(),
        language: j['language'] as String?,
        lossless: j['lossless'] == true,
        commentary: j['commentary'] == true,
        isDefault: j['default'] == true,
        forced: j['forced'] == true,
      );

  static List<MediaTrack> list(Object? raw) => raw is List
      ? [for (final e in raw) MediaTrack.fromJson(e as Map<String, dynamic>)]
      : const [];
}
