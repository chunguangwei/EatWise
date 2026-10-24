import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareDataExport(String filePath) async {
  await SharePlus.instance.share(
    ShareParams(files: <XFile>[XFile(filePath, mimeType: 'application/json')]),
  );
}

final dataExportShareProvider = Provider<Future<void> Function(String)>((ref) {
  return shareDataExport;
});
