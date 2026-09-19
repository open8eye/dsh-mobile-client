import 'package:flutter/material.dart';

import '../update/release_channels.dart';

/// User preferences, persisted as JSON next to the device list.
///
/// Everything here is a plain value so the whole object can round-trip through
/// `toJson`/`fromJson` without a schema migration step.
@immutable
class AppSettings {
  const AppSettings({
    this.localeCode,
    this.themeMode = ThemeMode.system,
    this.notificationsEnabled = true,
    this.notifyOnlyInBackground = true,
    this.keepScreenAwake = false,
    this.autoReconnect = true,
    this.petEnabled = false,
    this.petScale = 1.0,
    this.petOpacity = 1.0,
    this.petImagePath,
    this.activeDeviceId,
    this.autoOpenLastDevice = true,
    this.autoCheckUpdates = true,
    this.updateSource = UpdateSourcePreference.auto,
  });

  /// `null` follows the system language; otherwise 'zh' or 'en'.
  final String? localeCode;

  final ThemeMode themeMode;

  /// Mirror web notifications into system notifications.
  final bool notificationsEnabled;

  /// Stay quiet while the user is looking at the app.
  final bool notifyOnlyInBackground;

  /// Keep the screen on while a DSH session is on screen.
  final bool keepScreenAwake;

  /// Re-apply the stored password when the session is rejected.
  final bool autoReconnect;

  /// Android-only floating companion over the launcher.
  final bool petEnabled;
  final double petScale;
  final double petOpacity;

  /// Optional user-supplied character image; `null` uses the built-in one.
  final String? petImagePath;

  /// Device opened on launch.
  final String? activeDeviceId;

  final bool autoOpenLastDevice;

  /// Check both release hosts once per launch and offer anything newer.
  final bool autoCheckUpdates;

  /// Which release host the updater may ask.
  final UpdateSourcePreference updateSource;

  AppSettings copyWith({
    String? localeCode,
    bool clearLocale = false,
    ThemeMode? themeMode,
    bool? notificationsEnabled,
    bool? notifyOnlyInBackground,
    bool? keepScreenAwake,
    bool? autoReconnect,
    bool? petEnabled,
    double? petScale,
    double? petOpacity,
    String? petImagePath,
    bool clearPetImage = false,
    String? activeDeviceId,
    bool? autoOpenLastDevice,
    bool? autoCheckUpdates,
    UpdateSourcePreference? updateSource,
  }) {
    return AppSettings(
      localeCode: clearLocale ? null : (localeCode ?? this.localeCode),
      themeMode: themeMode ?? this.themeMode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notifyOnlyInBackground: notifyOnlyInBackground ?? this.notifyOnlyInBackground,
      keepScreenAwake: keepScreenAwake ?? this.keepScreenAwake,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      petEnabled: petEnabled ?? this.petEnabled,
      petScale: petScale ?? this.petScale,
      petOpacity: petOpacity ?? this.petOpacity,
      petImagePath: clearPetImage ? null : (petImagePath ?? this.petImagePath),
      activeDeviceId: activeDeviceId ?? this.activeDeviceId,
      autoOpenLastDevice: autoOpenLastDevice ?? this.autoOpenLastDevice,
      autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
      updateSource: updateSource ?? this.updateSource,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'localeCode': localeCode,
        'themeMode': themeMode.name,
        'notificationsEnabled': notificationsEnabled,
        'notifyOnlyInBackground': notifyOnlyInBackground,
        'keepScreenAwake': keepScreenAwake,
        'autoReconnect': autoReconnect,
        'petEnabled': petEnabled,
        'petScale': petScale,
        'petOpacity': petOpacity,
        'petImagePath': petImagePath,
        'activeDeviceId': activeDeviceId,
        'autoOpenLastDevice': autoOpenLastDevice,
        'autoCheckUpdates': autoCheckUpdates,
        'updateSource': updateSource.name,
      };

  static AppSettings fromJson(Map<String, Object?> json) {
    const fallback = AppSettings();
    return AppSettings(
      localeCode: json['localeCode'] is String ? json['localeCode'] as String : null,
      themeMode: ThemeMode.values.firstWhere(
        (value) => value.name == json['themeMode'],
        orElse: () => fallback.themeMode,
      ),
      notificationsEnabled: _bool(json['notificationsEnabled'], fallback.notificationsEnabled),
      notifyOnlyInBackground: _bool(json['notifyOnlyInBackground'], fallback.notifyOnlyInBackground),
      keepScreenAwake: _bool(json['keepScreenAwake'], fallback.keepScreenAwake),
      autoReconnect: _bool(json['autoReconnect'], fallback.autoReconnect),
      petEnabled: _bool(json['petEnabled'], fallback.petEnabled),
      petScale: _double(json['petScale'], fallback.petScale),
      petOpacity: _double(json['petOpacity'], fallback.petOpacity),
      petImagePath: json['petImagePath'] is String ? json['petImagePath'] as String : null,
      activeDeviceId: json['activeDeviceId'] is String ? json['activeDeviceId'] as String : null,
      autoOpenLastDevice: _bool(json['autoOpenLastDevice'], fallback.autoOpenLastDevice),
      autoCheckUpdates: _bool(json['autoCheckUpdates'], fallback.autoCheckUpdates),
      updateSource: UpdateSourcePreference.values.firstWhere(
        (value) => value.name == json['updateSource'],
        orElse: () => fallback.updateSource,
      ),
    );
  }

  static bool _bool(Object? value, bool fallback) => value is bool ? value : fallback;

  static double _double(Object? value, double fallback) =>
      value is num ? value.toDouble() : fallback;
}
