import '../models/dsh_device.dart';
import 'json_file_store.dart';

/// Reads and writes the saved device list.
class DeviceRepository {
  DeviceRepository({JsonFileStore? store})
      : _store = store ?? JsonFileStore('devices.json');

  final JsonFileStore _store;

  static const int _schemaVersion = 1;

  Future<List<DshDevice>> load() async {
    final document = await _store.readMap();
    final raw = document['devices'];
    if (raw is! List) return <DshDevice>[];
    final devices = <DshDevice>[];
    for (final entry in raw) {
      if (entry is Map<String, Object?>) {
        final device = DshDevice.fromJson(entry);
        if (device != null) devices.add(device);
      }
    }
    return devices;
  }

  Future<void> save(List<DshDevice> devices) async {
    await _store.writeMap(<String, Object?>{
      'version': _schemaVersion,
      'devices': devices.map((device) => device.toJson()).toList(),
    });
  }
}
