class Video {
  Video({
    required this.name,
    required this.type,
    required this.url,
    required this.key,
    required this.official,
  });

  final String name;
  final String type;
  final String url;
  final String key; // YouTube video id (for in-app preview)
  final bool official;

  factory Video.fromJson(Map<String, dynamic> j) => Video(
        name: (j['name'] ?? 'Video').toString(),
        type: (j['type'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        key: (j['key'] ?? '').toString(),
        official: j['official'] == true,
      );
}
