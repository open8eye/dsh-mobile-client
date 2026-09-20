import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../platform/app_platform.dart';
import 'diagnostics.dart';
import 'diagnostics_script.dart';

/// Assembles the text a user pastes into a bug report.
///
/// Everything here is written for a stranger to read: it has to say what the
/// phone is, what the WebView is, which page was being loaded, and what the app
/// saw happen — in that order, because that is the order a maintainer reads it
/// in. Secrets are already gone by the time they reach the log; this class adds
/// nothing and only formats.
class DiagnosticsReport {
  const DiagnosticsReport._();

  /// Collected once per run: the host does not change underneath us.
  static Map<String, String>? _deviceInfo;

  /// Host facts, cached. Empty on platforms without the bridge (iOS, tests).
  static Future<Map<String, String>> deviceInfo({bool refresh = false}) async {
    if (refresh) _deviceInfo = null;
    return _deviceInfo ??= await AppPlatform.deviceInfo();
  }

  /// Build the full report.
  ///
  /// [activeDevice] is the address currently open, if any. It is passed as a
  /// plain string and redacted on the way in.
  static Future<String> build({
    String? activeDevice,
    Map<String, Object?>? pageProbe,
    Diagnostics? diagnostics,
  }) async {
    final log = diagnostics ?? Diagnostics.instance;
    final info = await deviceInfo();
    final version = await _appVersion();

    final buffer = StringBuffer()
      ..writeln('DSH Mobile Client 诊断报告')
      ..writeln('生成时间: ${_stamp(DateTime.now())}')
      ..writeln()
      ..writeln('> 访问密码与会话 Cookie 已自动隐藏，可以直接公开。')
      ..writeln();

    buffer.writeln('## 环境');
    buffer.writeln('应用版本: $version');
    buffer.writeln('平台: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    if (info.isEmpty) {
      buffer.writeln('设备信息: 不可用（原生桥未实现）');
    } else {
      for (final key in info.keys) {
        buffer.writeln('$key: ${info[key]}');
      }
    }
    buffer.writeln();

    if (activeDevice != null && activeDevice.isNotEmpty) {
      buffer
        ..writeln('## 当前设备')
        ..writeln('地址: $activeDevice')
        ..writeln();
    }

    if (pageProbe != null && pageProbe.isNotEmpty) {
      buffer
        ..writeln('## 页面状态')
        ..writeln(DiagnosticsScript.describeProbe(pageProbe))
        ..writeln('原始: $pageProbe')
        ..writeln();
    }

    buffer.writeln('## 本次运行日志（${log.entries.length} 行）');
    if (log.entries.isEmpty) {
      buffer.writeln('(空)');
    } else {
      for (final entry in log.entries) {
        buffer.writeln(entry.format());
      }
    }
    buffer.writeln();

    final previous = log.previousRun?.trim();
    if (previous != null && previous.isNotEmpty) {
      buffer
        ..writeln('## 上一次运行的日志（尾部）')
        ..writeln(previous)
        ..writeln();
    }

    return buffer.toString();
  }

  /// Subject line for the share sheet.
  static Future<String> subject() async =>
      'DSH Mobile Client 诊断报告 (${await _appVersion()})';

  static Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version} (${info.buildNumber})';
    } on Exception {
      // package_info is unavailable in a bare test harness.
      return 'unknown';
    }
  }

  static String _stamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}
