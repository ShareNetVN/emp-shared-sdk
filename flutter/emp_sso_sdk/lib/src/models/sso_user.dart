import 'package:meta/meta.dart';

@immutable
class SsoUser {
  const SsoUser({
    required this.id,
    required this.email,
    this.fullName,
    this.avatarUrl,
    this.roles = const [],
    this.attributes = const {},
  });

  final String id;
  final String email;
  final String? fullName;
  final String? avatarUrl;
  final List<String> roles;
  final Map<String, dynamic> attributes;

  factory SsoUser.fromJson(Map<String, dynamic> json) {
    return SsoUser(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['fullName'] as String? ?? json['name'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      roles: (json['roles'] as List?)?.cast<String>() ?? const [],
      attributes: (json['attributes'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        if (fullName != null) 'fullName': fullName,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        'roles': roles,
        'attributes': attributes,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SsoUser && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);

  @override
  String toString() => 'SsoUser(id: $id, email: $email)';
}
