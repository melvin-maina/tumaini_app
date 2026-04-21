import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> exportBytesAsFile({
  required List<int> bytes,
  required String filename,
  required String mimeType,
  String? text,
  String? subject,
}) async {
  final file = XFile.fromData(
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    mimeType: mimeType,
    name: filename,
  );
  await Share.shareXFiles(
    [file],
    text: text,
    subject: subject,
  );
}
