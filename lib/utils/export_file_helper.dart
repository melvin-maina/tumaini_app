import 'export_file_helper_stub.dart'
    if (dart.library.html) 'export_file_helper_web.dart' as helper;

Future<void> exportBytesAsFile({
  required List<int> bytes,
  required String filename,
  required String mimeType,
  String? text,
  String? subject,
}) {
  return helper.exportBytesAsFile(
    bytes: bytes,
    filename: filename,
    mimeType: mimeType,
    text: text,
    subject: subject,
  );
}
