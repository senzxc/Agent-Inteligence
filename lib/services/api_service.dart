import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://163.128.212.19:5003';

  // Token disimpan selama aplikasi berjalan.
  static String? _token;

  static Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  static Future<Map<String, dynamic>> login(
    String stambuk,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'stambuk': stambuk, 'password': password}),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    // Simpan token hanya jika login berhasil.
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        data['success'] == true &&
        data['token'] != null) {
      _token = data['token'].toString();
    }

    return {'statusCode': response.statusCode, 'data': data};
  }

  static Future<Map<String, dynamic>> getKantor() async {
    final response = await http.get(Uri.parse('$baseUrl/api/kantor'));

    return {
      'statusCode': response.statusCode,
      'data': jsonDecode(response.body),
    };
  }

  // Helper untuk request tracking.
  static Future<Map<String, dynamic>> _trackingRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    if (_token == null) {
      throw Exception('Token belum tersedia. Silakan login ulang.');
    }

    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = _authHeaders;

    late http.Response response;

    switch (method) {
      case 'GET':
        response = await http.get(uri, headers: headers);
        break;
      case 'POST':
        response = await http.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
        break;
      default:
        throw Exception('Method API tidak didukung.');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      final responseBody = response.body.trimLeft();
      final contentType = response.headers['content-type'] ?? '';
      if (responseBody.startsWith('<') ||
          !contentType.contains('application/json')) {
        throw Exception(
          'Server tidak mengembalikan JSON untuk ${uri.path} '
          '(HTTP ${response.statusCode}). Pastikan backend terbaru sudah '
          'dijalankan dan endpoint tersebut tersedia.',
        );
      }
      rethrow;
    }

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Format respons API tracking tidak valid.');
    }
    final data = decoded;

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        data['message']?.toString() ??
            'Request gagal (HTTP ${response.statusCode}).',
      );
    }

    if (data['success'] == false) {
      throw Exception(data['message']?.toString() ?? 'Request tracking gagal.');
    }

    return {'statusCode': response.statusCode, 'data': data};
  }

  static Future<Map<String, dynamic>> startTracking() {
    return _trackingRequest('POST', '/api/agent-tracking/start');
  }

  static Future<Map<String, dynamic>> getTrackingStatus() {
    return _trackingRequest('GET', '/api/agent-tracking/status');
  }

  static Future<Map<String, dynamic>> sendTrackingLocation({
    required double latitude,
    required double longitude,
    required double accuracy,
    required double speed,
  }) {
    return _trackingRequest(
      'POST',
      '/api/agent-tracking/location',
      body: {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'speed': speed,
      },
    );
  }

  static Future<Map<String, dynamic>> stopTracking() {
    return _trackingRequest('POST', '/api/agent-tracking/stop');
  }

  static Future<Map<String, dynamic>> getAgents() {
    return _trackingRequest('GET', '/api/agent-tracking/agents');
  }

  
  // Mengambil daftar seluruh agen dari endpoint /api/agents.
  static Future<Map<String, dynamic>> getAgentList({
    String? kantor,
  }) {
    final queryParameters = <String, String>{};

    if (kantor != null && kantor.trim().isNotEmpty) {
      queryParameters['kantor'] = kantor.trim();
    }

    final query = queryParameters.isEmpty
        ? ''
        : '?${Uri(queryParameters: queryParameters).query}';

    return _trackingRequest('GET', '/api/agents$query');
  }

}
