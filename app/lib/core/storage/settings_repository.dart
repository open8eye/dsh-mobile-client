import '../models/app_settings.dart';
import 'json_file_store.dart';

/// Reads and writes user preferences.
class SettingsRepository {
  SettingsRepository({JsonFileStore? store})
      : _store = store ?? JsonFileStore('settings.json');

  final JsonFileStore _store;

  Future<AppSettings> load() async {
    final document = await _store.readMap();
    final raw = document['settings'];
    if (raw is! Map<String, Object?>) return const AppSettings();
    return AppSettings.fromJson(raw);
  }

  Future<void> save(AppSettings settings) async {
    await _store.writeMap(<String, Object?>{'settings': settings.toJson()});
  }
}
