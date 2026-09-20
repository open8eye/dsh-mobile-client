import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'log_entry.dart';
import 'redact.dart';

/// The app's single diagnostic log.
///
/// This is a process-wide instance rather than an injected provider on purpose:
/// it is written to from `main()` before the widget tree exists, from WebView
/// callbacks that outlive any particular build, and from error paths where
/// threading a dependency through is not an option. A logger that can be
/// unavailable at the moment something goes wrong is not a logger.
///
/// Redaction happens *here*, not at the call site, so a caller cannot forget.
class Diagnostics extends ChangeNotifier {
  Diagnostics({this.maxEntries = 400});

  /// Process-wide instance.
  static Diagnostics instance = Diagnostics();

  /// How many lines are kept in memory (and mirrored to disk).
  final int maxEntries;

  /// Beyond this the retained file is cut back on the next launch.
  static const int _maxFileChars = 256 * 1024;

  final Queue<LogEntry> _entries = Queue<LogEntry>();
  final List<String> _secrets = <String>[];

  /// Verbatim tail of the log written by the previous run.
  ///
  /// Kept unparsed: the interesting case is a crash or a white screen, and that
  /// run's lines are the evidence. Re-deriving timestamps from disk would add
  /// failure modes for nothing.
  String? _previousRun;

  File? _file;
  Timer? _flush;
  bool _dirty = false;
  bool _writing = false;

  List<LogEntry> get entries => List<LogEntry>.unmodifiable(_entries);

  String? get previousRun => _previousRun;

  bool get isEmpty => _entries.isEmpty && (_previousRun?.trim().isEmpty ?? true);

  /// Remember a value that must never appear in a report.
  ///
  /// Call this the moment a password is read from the keystore or typed by the
  /// user; everything logged afterwards is scrubbed against it.
  void registerSecret(String? secret) {
    if (secret == null || secret.length < 4) return;
    if (_secrets.contains(secret)) return;
    _secrets.add(secret);
  }

  /// Drop remembered secrets (on disconnect, so a later report cannot leak a
  /// password for a device the user has moved on from).
  void forgetSecrets() => _secrets.clear();

  void debug(String tag, String message) => log(LogLevel.debug, tag, message);

  void info(String tag, String message) => log(LogLevel.info, tag, message);

  void warn(String tag, String message) => log(LogLevel.warn, tag, message);

  void error(String tag, String message) => log(LogLevel.error, tag, message);

  void log(LogLevel level, String tag, String message) {
    final entry = LogEntry(
      time: DateTime.now(),
      level: level,
      tag: tag,
      message: Redact.text(message, secrets: _secrets),
    );
    _entries.addLast(entry);
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }

    _dirty = true;
    if (level == LogLevel.error) {
      // An error is exactly what a crash would take with it, so it goes to disk
      // now. Everything else is batched to keep logging off the hot path.
      unawaited(_flushNow());
    } else {
      _flush ??= Timer(const Duration(milliseconds: 800), () {
        _flush = null;
        unawaited(_flushNow());
      });
    }
    notifyListeners();
  }

  /// Read back the previous run and open the log file.
  Future<void> load() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}/diagnostics.log');
      _file = file;
      if (await file.exists()) {
        final text = await file.readAsString();
        _previousRun = text.length > _maxFileChars
            ? text.substring(text.length - _maxFileChars)
            : text;
      }
    } on Exception {
      // No plugin (tests) or no writable directory: logging stays in memory.
      // Losing the file is acceptable; refusing to start is not.
    }
    notifyListeners();
  }

  Future<void> clear() async {
    _entries.clear();
    _previousRun = null;
    _dirty = true;
    await _flushNow();
    notifyListeners();
  }

  Future<void> _flushNow() async {
    final file = _file;
    if (file == null || !_dirty || _writing) return;
    _writing = true;
    _dirty = false;
    try {
      final buffer = StringBuffer();
      for (final entry in _entries) {
        buffer.writeln(entry.format());
      }
      await file.writeAsString(buffer.toString(), flush: true);
    } on FileSystemException {
      // Logging must never be the reason something else fails.
    } finally {
      _writing = false;
    }
  }
}
