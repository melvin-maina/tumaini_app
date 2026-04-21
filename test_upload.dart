import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

void main() async {
  final _uploadUrl = 'https://script.google.com/macros/s/AKfycbyar6RJbDLbFjEa3Wz14H0rAbo1QHX6L6y-3t0nPptPlSDIla5B-j9Wsh7TaW0u_uXu/exec';
  final bytes = Uint8List.fromList(utf8.encode('Hello World'));
  final payload = <String, dynamic>{
    'fileName': 'test.txt',
    'fileMimeType': 'text/plain',
    'fileBase64': base64Encode(bytes),
    'adminEmail': 'tumainiestateserviceproviders@gmail.com',
    'userId': 'test_user',
    'userEmail': 'test@example.com',
    'providerName': 'Test Provider',
    'purpose': 'Testing',
    'notes': 'No notes',
  };

  try {
    var request = http.Request('POST', Uri.parse(_uploadUrl));
    request.headers.addAll({
      'Content-Type': 'text/plain;charset=utf-8',
      'Accept': 'application/json, text/plain, */*',
    });
    request.body = jsonEncode(payload);

    var client = http.Client();
    var streamedResponse = await client.send(request);
    var response = await http.Response.fromStream(streamedResponse);

    print('First Status Code: ${response.statusCode}');
    print('First Response Body: ${response.body}');

    if (response.isRedirect || response.statusCode == 302) {
      final location = response.headers['location'];
      print('Redirect Location: $location');
      if (location != null) {
        final redirectRes = await client.get(Uri.parse(location));
        print('Redirect Status Code: ${redirectRes.statusCode}');
        print('Redirect Response Body: ${redirectRes.body}');
      }
    }
  } catch (e) {
    print('Error: $e');
  }
}
