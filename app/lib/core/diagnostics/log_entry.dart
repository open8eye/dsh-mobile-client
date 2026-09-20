/// Severity of one diagnostic line.
enum LogLevel {
  debug('D'),
  info('I'),
  warn('W'),
  error('E');

  const LogLevel(this.letter);

  /// Single character used in the exported report.
  final String letter;
}

/// One line of the diagnostic log.
///
/// Deliberately plain text: this ends up pasted into a bug report, so it has to
/// stay readable and must never carry a secret. Everything reaching a
/// [LogEntry] is expected to have gone through `Redact` first.
class LogEntry {
  const LogEntry({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
  });

  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;

  String format() =>
      '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}.'
      '${_three(time.millisecond)} ${level.letter}/$tag  $message';

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _three(int value) => value.toString().padLeft(3, '0');

  @override
  String toString() => format();
}
