import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/job.dart';
import 'storage_service.dart';

class ApiService {
  static Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> login(String username, String password) async {
    final baseUrl = await StorageService.getBackendUrl();
    final url = Uri.parse('$baseUrl/api/v1/auth/login');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final token = data['token'] as String;
      await StorageService.setToken(token);
      return data;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Login failed (${response.statusCode})');
    }
  }

  static Future<List<PrintJob>> getQueue() async {
    final baseUrl = await StorageService.getBackendUrl();
    final url = Uri.parse('$baseUrl/api/v1/jobs/queue');

    final response = await http.get(url, headers: await _headers());

    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list.map((item) => PrintJob.fromJson(item as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Failed to fetch print queue (${response.statusCode})');
    }
  }

  static Future<List<PrintJob>> getHistory() async {
    final baseUrl = await StorageService.getBackendUrl();
    final url = Uri.parse('$baseUrl/api/v1/jobs/history');

    final response = await http.get(url, headers: await _headers());

    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list.map((item) => PrintJob.fromJson(item as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Failed to fetch job history (${response.statusCode})');
    }
  }

  static Future<void> updateSettings(String jobId, String fileId, PrintSettings settings) async {
    final baseUrl = await StorageService.getBackendUrl();
    final url = Uri.parse('$baseUrl/api/v1/jobs/$jobId/settings');

    final response = await http.patch(
      url,
      headers: await _headers(),
      body: jsonEncode({
        'fileId': fileId,
        'settings': settings.toJson(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update print settings');
    }
  }

  static Future<void> updateStatus(
    String jobId,
    String status, {
    String? printerName,
    String? errorMessage,
  }) async {
    final baseUrl = await StorageService.getBackendUrl();
    final url = Uri.parse('$baseUrl/api/v1/jobs/$jobId/status');

    final response = await http.post(
      url,
      headers: await _headers(),
      body: jsonEncode({
        'status': status,
        if (printerName != null) 'printerName': printerName,
        if (errorMessage != null) 'errorMessage': errorMessage,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update job status to $status');
    }
  }

  static Future<Uint8List> downloadFileBytes(String jobId, String fileId) async {
    final baseUrl = await StorageService.getBackendUrl();
    final url = Uri.parse('$baseUrl/api/v1/jobs/$jobId/files/$fileId/stream');

    final response = await http.get(url, headers: await _headers());

    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Failed to download file stream from backend (${response.statusCode})');
    }
  }

  static Future<Uint8List> downloadComposedPdfBytes(String jobId) async {
    final baseUrl = await StorageService.getBackendUrl();
    final url = Uri.parse('$baseUrl/api/v1/jobs/$jobId/composed-pdf');

    final response = await http.get(url, headers: await _headers());

    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Failed to download composed image PDF (${response.statusCode})');
    }
  }
}
