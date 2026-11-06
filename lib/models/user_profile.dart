import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'user_role.dart';

class UserProfile {
  final String id;
  final String username;
  final String displayName;
  final UserRole role;
  final String passwordHash;
  final String salt;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.passwordHash,
    required this.salt,
    this.isActive = true,
    required this.createdAt,
    this.lastLoginAt,
  });

  /// Cryptographic salted SHA-256 password hash generator
  static String hashPassword(String password, String salt) {
    const pepper = 'warloc_pos_secure_pepper_2026';
    final bytes = utf8.encode('$salt:$password:$pepper');
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Random cryptographic salt generator
  static String generateSalt([int length = 16]) {
    final rand = Random.secure();
    final values = List<int>.generate(length, (_) => rand.nextInt(256));
    return base64Url.encode(values);
  }

  /// Constant-time string comparison to mitigate timing side-channels
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Factory helper to create a new user profile from plain password
  factory UserProfile.create({
    required String username,
    required String displayName,
    required UserRole role,
    required String plainPassword,
    String? id,
  }) {
    final salt = generateSalt();
    final hash = hashPassword(plainPassword, salt);
    return UserProfile(
      id: id ?? 'u_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}',
      username: username.trim().toLowerCase(),
      displayName: displayName.trim(),
      role: role,
      passwordHash: hash,
      salt: salt,
      isActive: true,
      createdAt: DateTime.now(),
    );
  }

  /// Verifies input password against stored salt and hash
  bool verifyPassword(String plainPassword) {
    if (!isActive || passwordHash.isEmpty || salt.isEmpty) return false;
    if (passwordHash.startsWith('pbkdf2-sha256:')) {
      final parts = passwordHash.split(':');
      if (parts.length != 3 || parts[1] != '600000') return false;
      return _constantTimeEquals(_derivePassword([plainPassword, salt]), parts[2]);
    }
    final computedHash = hashPassword(plainPassword, salt);
    return _constantTimeEquals(computedHash, passwordHash);
  }

  Future<bool> verifyPasswordAsync(String password) async {
    if (!passwordHash.startsWith('pbkdf2-sha256:')) return verifyPassword(password);
    if (!isActive || passwordHash.split(':').length != 3 || passwordHash.split(':')[1] != '600000') return false;
    final hash = await compute(_derivePassword, [password, salt]);
    return _constantTimeEquals(hash, passwordHash.split(':')[2]);
  }

  Future<UserProfile> withSecurePassword(String password) async {
    if (password.length < 6 || password.length > 128) throw ArgumentError('Password harus minimal 6 karakter.');
    final newSalt = generateSalt();
    final hash = await compute(_derivePassword, [password, newSalt]);
    return copyWith(passwordHash: 'pbkdf2-sha256:600000:$hash', salt: newSalt);
  }

  /// Returns a copy with freshly salted SHA-256 password credentials
  UserProfile withUpdatedPassword(String plainPassword) {
    final newSalt = generateSalt();
    final newHash = hashPassword(plainPassword, newSalt);
    return copyWith(
      salt: newSalt,
      passwordHash: newHash,
    );
  }

  UserProfile copyWith({
    String? id,
    String? username,
    String? displayName,
    UserRole? role,
    String? passwordHash,
    String? salt,
    bool? isActive,
    DateTime? createdAt,
    DateTime? lastLoginAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      passwordHash: passwordHash ?? this.passwordHash,
      salt: salt ?? this.salt,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'displayName': displayName,
      'role': role.name,
      'passwordHash': passwordHash,
      'salt': salt,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'lastLoginAt': lastLoginAt?.toIso8601String(),
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String? ?? 'u_unknown',
      username: (map['username'] as String? ?? '').toLowerCase(),
      displayName: map['displayName'] as String? ?? 'Staff Warloc',
      role: UserRole.values.firstWhere(
        (r) => r.name == map['role'],
        orElse: () => UserRole.barista,
      ),
      passwordHash: map['passwordHash'] as String? ?? '',
      salt: map['salt'] as String? ?? '',
      isActive: map['isActive'] as bool? ?? true,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastLoginAt: map['lastLoginAt'] != null
          ? DateTime.tryParse(map['lastLoginAt'] as String)
          : null,
    );
  }
}

String _derivePassword(List<String> input) {
  final hmac = Hmac(sha256, utf8.encode(input[0]));
  var block = hmac.convert([...utf8.encode(input[1]), 0, 0, 0, 1]).bytes;
  final result = List<int>.from(block);
  for (var i = 1; i < 600000; i++) {
    block = hmac.convert(block).bytes;
    for (var j = 0; j < result.length; j++) { result[j] ^= block[j]; }
  }
  return base64Url.encode(result);
}
