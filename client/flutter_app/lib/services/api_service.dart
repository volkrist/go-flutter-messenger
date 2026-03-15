import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../config.dart';
import '../models/message.dart';
import '../models/room.dart';
import '../models/user.dart';
import 'auth_service.dart';

class ApiService {
  ApiService({String? baseUrl}) : baseUrl = baseUrl ?? backendHttpUrl;
  final String baseUrl;

  /// Только Authorization — для multipart (upload) Content-Type не задаём.
  Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService().getSavedToken();
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Authorization + JSON Content-Type — для обычных JSON-запросов.
  Future<Map<String, String>> _jsonHeaders() async {
    final h = await _authHeaders();
    h['Content-Type'] = 'application/json';
    return h;
  }

  Future<List<Room>> getRooms(String username) async {
    final uri = Uri.parse('$baseUrl/rooms').replace(
      queryParameters: {'username': username},
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('Failed to load chats');
    final list = jsonDecode(res.body) as List<dynamic>;
    return list.map((e) => Room.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Room> createGroupRoom(String name, String creatorUsername) async {
    final res = await http.post(
      Uri.parse('$baseUrl/rooms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'creator_username': creatorUsername,
      }),
    );

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(res.body.isNotEmpty ? res.body : 'Could not create chat');
    }

    return Room.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<Room> createPrivateRoom(String currentUsername, String targetUsername) async {
    final res = await http.post(
      Uri.parse('$baseUrl/rooms/private'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'current_username': currentUsername,
        'target_username': targetUsername,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(res.body.isNotEmpty ? res.body : 'Could not create private chat');
    }
    return Room.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<User>> searchUsers(String query, String currentUsername) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final uri = Uri.parse('$baseUrl/users/search').replace(
      queryParameters: {
        'q': trimmed,
        'current_username': currentUsername,
      },
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception(res.body.isNotEmpty ? res.body : 'Failed to search users');
    }

    final list = jsonDecode(res.body) as List<dynamic>;
    return list.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<User>> getRoomMembers(int roomId) async {
    final uri = Uri.parse('$baseUrl/rooms/members').replace(
      queryParameters: {'roomId': roomId.toString()},
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception(res.body.isNotEmpty ? res.body : 'Failed to load members');
    }

    final list = jsonDecode(res.body) as List<dynamic>;
    return list.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> renameRoom(int roomId, String name) async {
    final res = await http.put(
      Uri.parse('$baseUrl/rooms/rename'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'room_id': roomId,
        'name': name,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception(res.body.isNotEmpty ? res.body : 'Could not rename room');
    }
  }

  Future<void> leaveRoom(int roomId, String username) async {
    final res = await http.post(
      Uri.parse('$baseUrl/rooms/leave'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'room_id': roomId,
        'username': username,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception(res.body.isNotEmpty ? res.body : 'Could not leave room');
    }
  }

  Future<List<ChatMessage>> getMessages(int roomId, String username) async {
    final uri = Uri.parse('$baseUrl/messages').replace(
      queryParameters: {
        'roomId': roomId.toString(),
        'username': username,
      },
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('Failed to load messages');
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChatMessage>> searchMessages(int roomId, String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final uri = Uri.parse('$baseUrl/messages/search').replace(
      queryParameters: {
        'room_id': roomId.toString(),
        'q': trimmed,
      },
    );
    final res = await http.get(uri, headers: await _jsonHeaders());
    if (res.statusCode != 200) {
      throw Exception(res.body.isNotEmpty ? res.body : 'Search failed');
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markMessagesRead(int roomId, String username) async {
    final res = await http.post(
      Uri.parse('$baseUrl/messages/read'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'room_id': roomId,
        'username': username,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(res.body.isNotEmpty ? res.body : 'Failed to mark messages read');
    }
  }

  Future<void> registerDeviceToken({
    required String username,
    required String token,
    required String platform,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/devices/register'),
      headers: await _jsonHeaders(),
      body: jsonEncode({
        'username': username,
        'token': token,
        'platform': platform,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to register device token: ${response.body}');
    }
  }

  Future<String> uploadImage(File file) async {
    final uri = Uri.parse('$baseUrl/upload/image');

    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(await _authHeaders());

    final mimeType = lookupMimeType(file.path) ?? 'image/jpeg';
    final mimeParts = mimeType.split('/');

    final multipartFile = await http.MultipartFile.fromPath(
      'image',
      file.path,
      contentType: MediaType(mimeParts[0], mimeParts[1]),
    );

    request.files.add(multipartFile);

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception('Failed to upload image: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['image_url'] as String;
  }
}
