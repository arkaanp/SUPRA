/// Application user (ERD entity USER).
class User {
  final String id;
  final String fullName;
  final String email;
  final String? avatarUrl;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.fullName,
    required this.email,
    this.avatarUrl,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    fullName: json['full_name'] as String,
    email: json['email'] as String,
    avatarUrl: json['avatar_url'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'full_name': fullName,
    'email': email,
    'avatar_url': avatarUrl,
    'created_at': createdAt.toIso8601String(),
  };

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
  }
}
