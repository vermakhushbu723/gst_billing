import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// On phones a "download" opens the share sheet (Save to Files, Drive, WhatsApp...).
Future<void> saveBytes(Uint8List bytes, String name, String mime) async {
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(bytes, mimeType: mime, name: name)],
    fileNameOverrides: [name],
  ));
}
