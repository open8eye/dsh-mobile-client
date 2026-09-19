import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../storage/settings_repository.dart';
import '../update/release_channels.dart';

/// Holds user preferences and writes them back on every change.
class SettingsController extends ChangeNotifier {
  SettingsController({required SettingsRepository repository}) : _repository = repository;

  final SettingsRepository _repository;

  AppSettings _settings = const AppSettings();
  bool _loaded = false;

  AppSettings get settings => _settings;
  bool get loaded => _loaded;

  Future<void> load() async {
    _settings = await _repository.load();
    _loaded = true;
    notifyListeners();
  }

  Future<void> update(AppSettings next) async {
    _settings = next;
    notifyListeners();
    await _repository.save(next);
  }

  /// Resolve the effective locale code ('zh' or 'en') against [systemLocales].
  String resolveLocaleCode(List<Locale> systemLocales) {
    final explicit = _settings.localeCode;
    if (explicit != null) return explicit;
    for (final locale in systemLocales) {
      if (locale.languageCode == 'zh') return 'zh';
      if (locale.languageCode == 'en') return 'en';
    }
    return 'en';
  }

  Future<void> setLocaleCode(String? code) =>
      update(_settings.copyWith(localeCode: code, clearLocale: code == null));

  Future<void> setThemeMode(ThemeMode mode) => update(_settings.copyWith(themeMode: mode));

  Future<void> setNotificationsEnabled(bool value) =>
      update(_settings.copyWith(notificationsEnabled: value));

  Future<void> setNotifyOnlyInBackground(bool value) =>
      update(_settings.copyWith(notifyOnlyInBackground: value));

  Future<void> setKeepScreenAwake(bool value) =>
      update(_settings.copyWith(keepScreenAwake: value));

  Future<void> setAutoReconnect(bool value) => update(_settings.copyWith(autoReconnect: value));

  Future<void> setAutoOpenLastDevice(bool value) =>
      update(_settings.copyWith(autoOpenLastDevice: value));

  Future<void> setPetEnabled(bool value) => update(_settings.copyWith(petEnabled: value));

  Future<void> setPetScale(double value) => update(_settings.copyWith(petScale: value));

  Future<void> setPetOpacity(double value) => update(_settings.copyWith(petOpacity: value));

  Future<void> setPetImagePath(String? path) =>
      update(_settings.copyWith(petImagePath: path, clearPetImage: path == null));

  Future<void> setActiveDeviceId(String? id) =>
      update(_settings.copyWith(activeDeviceId: id));

  Future<void> setAutoCheckUpdates(bool value) =>
      update(_settings.copyWith(autoCheckUpdates: value));

  Future<void> setUpdateSource(UpdateSourcePreference source) =>
      update(_settings.copyWith(updateSource: source));
}
