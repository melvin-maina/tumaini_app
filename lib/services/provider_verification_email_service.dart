import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ProviderVerificationEmailService {
  static const String _scriptUrl =
      'https://script.google.com/macros/s/AKfycbysbPSKqfuZgQZ0yigB8BIwe18iI3JRBXwzQj1ZE9osnFz70vKIGTC8TI7qsUuwZQOO/exec';

  bool _responseLooksSuccessful(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.contains('"success":true')) return true;
    if (trimmed.contains('"success" : true')) return true;
    if (trimmed.toLowerCase().contains('"action":"provider_verification_email"')) return true;
    return false;
  }

  Future<bool> sendVerificationDecisionEmail({
    required String providerName,
    required String providerEmail,
    required String decision,
    String? rejectionReason,
  }) async {
    final trimmedEmail = providerEmail.trim();
    if (trimmedEmail.isEmpty) return false;

    final normalizedDecision = decision.trim().toLowerCase();
    if (normalizedDecision != 'approved' && normalizedDecision != 'rejected') {
      throw Exception('Unsupported verification decision: $decision');
    }

    final payload = <String, dynamic>{
      'action': 'provider_verification_email',
      'providerName': providerName.trim().isEmpty ? 'Service Provider' : providerName.trim(),
      'providerEmail': trimmedEmail,
      'decision': normalizedDecision,
      'reason': (rejectionReason ?? '').trim(),
    };

    final client = http.Client();
    try {
      var request = http.Request('POST', Uri.parse(_scriptUrl));
      request.headers.addAll(const {
        'Content-Type': 'text/plain;charset=utf-8',
        'Accept': 'application/json, text/plain, */*',
      });
      request.body = jsonEncode(payload);

      var streamedResponse = await client.send(request).timeout(const Duration(seconds: 30));
      var response = await http.Response.fromStream(streamedResponse);

      if (response.isRedirect || response.statusCode == 302 || response.statusCode == 303) {
        final location = response.headers['location'];
        if (location != null && location.isNotEmpty) {
          response = await client.get(Uri.parse(location)).timeout(const Duration(seconds: 30));
        }
      }

      if (response.statusCode != 200) {
        throw Exception('Email request failed (${response.statusCode}).');
      }

      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          return body['success'] == true;
        }
      } catch (_) {
        return _responseLooksSuccessful(response.body);
      }

      return _responseLooksSuccessful(response.body);
    } on TimeoutException {
      return false;
    } finally {
      client.close();
    }
  }
}
