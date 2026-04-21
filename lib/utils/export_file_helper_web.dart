import 'dart:html' as html;

Future<void> exportBytesAsFile({
  required List<int> bytes,
  required String filename,
  required String mimeType,
  String? text,
  String? subject,
}) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';

  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
