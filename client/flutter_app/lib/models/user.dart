class User {
  final int id;
  final String email;
  final String username;
  final String displayName;
  final String? avatar;

  const User({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    this.avatar,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      email: json['email'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String,
      avatar: json['avatar'] as String?,
    );
  }
}
