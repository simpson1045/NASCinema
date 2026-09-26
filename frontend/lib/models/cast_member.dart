/// One top-billed actor for the movie page's Cast row.
class CastMember {
  const CastMember({required this.name, this.character, this.photo});

  final String name;
  final String? character;
  final String? photo; // TMDB w185 headshot URL

  factory CastMember.fromJson(Map<String, dynamic> j) => CastMember(
        name: (j['name'] ?? '').toString(),
        character: j['character'] as String?,
        photo: j['photo'] as String?,
      );
}
