import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class UploadedDocument {
  final String fileName;
  final String fileMimeType;
  final int sizeBytes;
  final String responseBody;
  final String? fileUrl;
  final String? downloadUrl;
  final String? fileId;

  const UploadedDocument({
    required this.fileName,
    required this.fileMimeType,
    required this.sizeBytes,
    required this.responseBody,
    this.fileUrl,
    this.downloadUrl,
    this.fileId,
  });

  Map<String, dynamic> toMap() {
    return {
      'fileName': fileName,
      'fileMimeType': fileMimeType,
      'sizeBytes': sizeBytes,
      'responseBody': responseBody,
      'fileUrl': fileUrl,
      'downloadUrl': downloadUrl,
      'fileId': fileId,
      'addedAt': DateTime.now().toIso8601String(),
    };
  }
}

class DocumentUploadService {
  static const String _uploadUrl =
      'https://script.google.com/macros/s/AKfycbysbPSKqfuZgQZ0yigB8BIwe18iI3JRBXwzQj1ZE9osnFz70vKIGTC8TI7qsUuwZQOO/exec';
  static const String _adminEmail = 'tumainiestateserviceproviders@gmail.com';
  static const int maxSizeBytes = 10 * 1024 * 1024;
  static const Set<String> allowedMimes = <String>{
    'application/pdf',
    'image/jpeg',
    'image/png',
  };

  // Preferred Apps Script success JSON:
  // {
  //   "success": true,
  //   "fileId": "...",
  //   "fileUrl": "https://drive.google.com/file/d/.../view",
  //   "downloadUrl": "https://drive.google.com/uc?export=download&id=..."
  // }
  String? _parseUrl(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    return text;
  }

  String? _parseFileId(dynamic value) {
    final id = value?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    return RegExp(r'^[a-zA-Z0-9_-]{10,}$').hasMatch(id) ? id : null;
  }

  Map<String, String?> _extractUploadMetadata(String responseBody) {
    String? fileUrl;
    String? downloadUrl;
    String? fileId;

    void visit(dynamic node) {
      if (node == null) return;
      if (node is Map) {
        fileUrl = fileUrl ??
            _parseUrl(node['fileUrl']) ??
            _parseUrl(node['viewUrl']) ??
            _parseUrl(node['webViewLink']) ??
            _parseUrl(node['url']) ??
            _parseUrl(node['link']);
        downloadUrl = downloadUrl ??
            _parseUrl(node['downloadUrl']) ??
            _parseUrl(node['directDownloadUrl']) ??
            _parseUrl(node['fileDownloadUrl']);
        fileId = fileId ??
            _parseFileId(node['fileId']) ??
            _parseFileId(node['fileID']) ??
            _parseFileId(node['driveFileId']) ??
            _parseFileId(node['id']);

        for (final value in node.values) {
          visit(value);
        }
        return;
      }
      if (node is Iterable) {
        for (final item in node) {
          visit(item);
        }
        return;
      }
      final text = node.toString().trim();
      if (text.isEmpty) return;
      fileUrl = fileUrl ?? _parseUrl(text);
      final pathMatch = RegExp(r'file/d/([a-zA-Z0-9_-]{10,})').firstMatch(text);
      fileId = fileId ?? pathMatch?.group(1);
      final keyMatch = RegExp(
        "(?:fileId|fileID|driveFileId|id)\\s*[:=]\\s*['\\\"]?([a-zA-Z0-9_-]{10,})",
      ).firstMatch(text);
      fileId = fileId ?? keyMatch?.group(1);
    }

    try {
      visit(jsonDecode(responseBody));
    } catch (_) {
      visit(responseBody);
    }

    fileUrl ??= fileId != null ? 'https://drive.google.com/file/d/$fileId/view' : null;
    downloadUrl ??= fileId != null
        ? 'https://drive.google.com/uc?export=download&id=$fileId'
        : null;

    return {
      'fileUrl': fileUrl,
      'downloadUrl': downloadUrl,
      'fileId': fileId,
    };
  }

  Future<UploadedDocument> uploadDocument({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String userId,
    required String userEmail,
    required String providerName,
    required String purpose,
    String? notes,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('Selected file is empty.');
    }
    if (bytes.length > maxSizeBytes) {
      throw Exception('File too large. Maximum is 10MB.');
    }
    if (!allowedMimes.contains(mimeType)) {
      throw Exception('Only PDF, JPG, and PNG files are allowed.');
    }

    final payload = <String, dynamic>{
      'fileName': fileName,
      'fileMimeType': mimeType,
      'fileBase64': base64Encode(bytes),
      'adminEmail': _adminEmail,
      'userId': userId,
      'userEmail': userEmail,
      'providerName': providerName.trim(),
      'purpose': purpose.trim(),
      'notes': (notes ?? '').trim(),
    };

    final uploadUri = Uri.parse(_uploadUrl.trim());
    http.Response response;

    try {
      var request = http.Request('POST', uploadUri);
      request.headers.addAll({
        'Content-Type': 'text/plain;charset=utf-8',
        'Accept': 'application/json, text/plain, */*',
      });
      request.body = jsonEncode(payload);

      var client = http.Client();
      var streamedResponse = await client.send(request).timeout(const Duration(seconds: 45));
      response = await http.Response.fromStream(streamedResponse);

      // Google Apps Script always returns 302 for doPost, so we must follow it manually
      if (response.isRedirect || response.statusCode == 302 || response.statusCode == 303) {
        final location = response.headers['location'];
        if (location != null) {
          response = await client.get(Uri.parse(location)).timeout(const Duration(seconds: 45));
        }
      }
      client.close();
    } on TimeoutException {
      throw Exception('Upload timed out while contacting Google Apps Script.');
    } on http.ClientException catch (e) {
      throw Exception(
        'Upload could not reach Google Apps Script. '
        'This is usually a browser CORS or web app deployment issue. '
        'Details: ${e.message}',
      );
    }

    if (response.statusCode != 200) {
      throw Exception('Upload failed (${response.statusCode}): ${response.body}');
    }

    // Checking if Apps Script returned a JSON error
    try {
      final jsonResponse = jsonDecode(response.body);
      if (jsonResponse['success'] == false) {
        throw Exception(jsonResponse['error'] ?? 'Unknown error from Apps Script');
      }
    } catch (_) {
      // Not JSON or parse error, fallback to returning the whole body
    }

    final metadata = _extractUploadMetadata(response.body);

    return UploadedDocument(
      fileName: fileName,
      fileMimeType: mimeType,
      sizeBytes: bytes.length,
      responseBody: response.body,
      fileUrl: metadata['fileUrl'],
      downloadUrl: metadata['downloadUrl'],
      fileId: metadata['fileId'],
    );
  }
}
