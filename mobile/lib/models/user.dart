/// Application user (ERD entity USER).
class User {
  final String id;
  final String username;
  final String email;
  final String? avatarUrl;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.username,
    required this.email,
    this.avatarUrl,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    username: json['username'] as String,
    email: json['email'] as String,
    avatarUrl: json['avatar_url'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'email': email,
    'avatar_url': avatarUrl,
    'created_at': createdAt.toIso8601String(),
  };

  static const usernameHint = 'Use 3–32 letters, numbers or underscores.';
  static final _handle = RegExp(r'^[A-Za-z0-9_]{3,32}$');
  static bool isValidUsername(String value) => _handle.hasMatch(value.trim());

  String get initials => username.isEmpty ? '?' : username[0].toUpperCase();
}
