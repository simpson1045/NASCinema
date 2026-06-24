class Video {
  Video({required this.name, required this.type, required this.url});

  final String name;
  final String type;
  final String url;

  factory Video.fromJson(Map<String, dynamic> j) => Video(
        name: (j['name'] ?? 'Video').toString(),
        type: (j['type'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
      );
}
