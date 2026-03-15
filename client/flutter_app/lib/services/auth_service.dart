import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/user.dart';
import 'session_storage.dart';

class AuthResult {
  final String token;
  final User user;

  AuthResult({
    required this.token,
    required this.user,
  });
}

class AuthService {
  final SessionStorage _storage = SessionStorage();

  Future<AuthResult> register({
    required String email,
    required String password,
    required String username,
    required String displayName,
  }) async {
    final response = await http.post(
      Uri.parse('$backendHttpUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'username': username,
        'displayName': displayName,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      final msg = response.body.isNotEmpty ? response.body : 'Ошибка регистрации';
      throw Exception(msg);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['token'] as String;
    final user = User.fromJson(data['user'] as Map<String, dynamic>);

    await _storage.saveToken(token);

    return AuthResult(token: token, user: user);
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$backendHttpUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Неверный email или пароль');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['token'] as String;
    final user = User.fromJson(data['user'] as Map<String, dynamic>);

    await _storage.saveToken(token);

    return AuthResult(token: token, user: user);
  }

  Future<User?> getMe() async {
    final token = await _storage.getToken();
    if (token == null || token.isEmpty) return null;

    final response = await http.get(
      Uri.parse('$backendHttpUrl/me'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      await _storage.clearToken();
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return User.fromJson(data);
  }

  Future<User> updateMe({
    required String username,
    required String displayName,
  }) async {
    final token = await _storage.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Нет токена');
    }

    final response = await http.put(
      Uri.parse('$backendHttpUrl/me'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'username': username,
        'displayName': displayName,
      }),
    );

    if (response.statusCode != 200) {
      final msg = response.body.isNotEmpty ? response.body : 'Не удалось обновить профиль';
      throw Exception(msg);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return User.fromJson(data);
  }

  Future<String?> getSavedToken() async {
    return _storage.getToken();
  }

  Future<void> logout() async {
    await _storage.clearToken();
  }
}
