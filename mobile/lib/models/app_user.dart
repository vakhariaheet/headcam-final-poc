/// The signed-in UmpireHat account, from the real auth backend
/// (`backend/`), distinct from the mocked broadcast-channel OAuth.
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    email: json['email'] as String,
    firstName: json['firstName'] as String,
    lastName: json['lastName'] as String?,
    role: json['role'] as String,
  );

  final String id;
  final String email;
  final String firstName;
  final String? lastName;
  final String role;

  String get displayName =>
      lastName == null ? firstName : '$firstName $lastName';
}
