import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Small helper for the app's JSON documents.
///
/// The device list and the settings both live in the application support
/// directory as human-readable JSON: easy to inspect, easy to back up, and no
/// database dependency for what is at most a few dozen records.
class JsonFileStore {
  JsonFileStore(this.fileName);

  final String fileName;
  File? _cached;

  Future<File> _file() async {
    final cached = _cached;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$fileName');
    _cached = file;
    return file;
  }

  Future<Map<String, Object?>> readMap() async {
    try {
      final file = await _file();
      if (!await file.exists()) return <String, Object?>{};
      final text = await file.readAsString();
      if (text.trim().isEmpty) return <String, Object?>{};
      final decoded = jsonDecode(text);
      if (decoded is Map<String, Object?>) return decoded;
      return <String, Object?>{};
    } on Exception {
      // A corrupt document must not brick the app: fall back to defaults and
      // let the next write replace it.
      return <String, Object?>{};
    }
  }

  Future<void> writeMap(Map<String, Object?> value) async {
    final file = await _file();
    const encoder = JsonEncoder.withIndent('  ');
    // Write-then-rename so a crash mid-write cannot truncate the old document.
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(encoder.convert(value), flush: true);
    await temp.rename(file.path);
  }
}
