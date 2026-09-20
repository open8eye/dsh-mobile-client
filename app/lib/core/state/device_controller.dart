import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../dsh/dsh_endpoint.dart';
import '../models/dsh_device.dart';
import '../storage/device_repository.dart';
import '../storage/secret_store.dart';

/// Owns the saved device list, the active device, and the password keystore.
///
/// Passwords are never cached in this object: every read goes to the platform
/// keystore so a memory dump or a crash report cannot leak them.
class DeviceController extends ChangeNotifier {
  DeviceController({
    required DeviceRepository repository,
    required SecretStore secrets,
    Uuid? uuid,
  })  : _repository = repository,
        _secrets = secrets,
        _uuid = uuid ?? const Uuid();

  final DeviceRepository _repository;
  final SecretStore _secrets;
  final Uuid _uuid;

  final List<DshDevice> _devices = <DshDevice>[];
  String? _activeDeviceId;
  bool _loaded = false;

  List<DshDevice> get devices => List<DshDevice>.unmodifiable(_devices);

  bool get loaded => _loaded;

  bool get isEmpty => _devices.isEmpty;

  String? get activeDeviceId => _activeDeviceId;

  DshDevice? get activeDevice {
    final id = _activeDeviceId;
    if (id == null) return null;
    for (final device in _devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  DshDevice? byId(String id) {
    for (final device in _devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  Future<void> load({String? initialActiveDeviceId}) async {
    final loaded = await _repository.load();
    _devices
      ..clear()
      ..addAll(loaded);
    _activeDeviceId = initialActiveDeviceId;
    if (_activeDeviceId != null && byId(_activeDeviceId!) == null) {
      _activeDeviceId = _devices.isEmpty ? null : _devices.first.id;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<String?> passwordFor(String deviceId) => _secrets.readPassword(deviceId);

  /// Save (or clear) the access password for [deviceId].
  ///
  /// Returns an error message when the keystore rejected the write, so the UI
  /// can say so instead of silently losing the password.
  Future<String?> setPassword(String deviceId, String? password) async {
    try {
      await _secrets.writePassword(deviceId, password);
    } on SecretStoreException {
      return 'keystore';
    }
    _replace(byId(deviceId)?.copyWith(hasPassword: password != null && password.isNotEmpty));
    await _persist();
    return null;
  }

  /// Add a device from a scanned or typed endpoint.
  ///
  /// Re-adding an address that already exists updates that entry instead of
  /// creating a duplicate, which is what a second scan of the same QR code
  /// should do.
  ///
  /// [altBaseUrl] is the server's other address. Pass `null` to leave whatever
  /// is stored alone — a scan knows nothing about it — or an empty string to
  /// clear it, which is what the edit form means by an empty field.
  Future<DshDevice> addFromEndpoint(
    DshEndpoint endpoint, {
    String? name,
    String? password,
    String? altBaseUrl,
  }) async {
    final existing = _findByAddress(endpoint.baseUrl);
    final resolvedName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (existing?.name ?? DshDevice.defaultNameFor(endpoint.host, endpoint.kind));

    final providedPassword = password != null && password.isNotEmpty;
    // Scanning a QR code again must not silently drop a password the user
    // already stored for this address.
    final hasPassword = providedPassword || (existing?.hasPassword ?? false);

    final device = DshDevice(
      id: existing?.id ?? _uuid.v4(),
      name: resolvedName,
      baseUrl: endpoint.baseUrl,
      kind: endpoint.kind,
      altBaseUrls: altBaseUrl == null
          ? (existing?.altBaseUrls ?? const <String>[])
          : _alternatesFor(altBaseUrl, endpoint.baseUrl),
      hasPassword: hasPassword,
      lastConnectedAt: existing?.lastConnectedAt,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );

    if (providedPassword) {
      await _secrets.writePassword(device.id, password);
    }

    if (existing == null) {
      _devices.add(device);
    } else {
      _replace(device);
    }
    _activeDeviceId = device.id;
    await _persist();
    return device;
  }

  Future<void> rename(String deviceId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _replace(byId(deviceId)?.copyWith(name: trimmed));
    await _persist();
  }

  /// Change a device's address and/or nickname from the edit screen.
  ///
  /// The access password is deliberately not editable here. It is captured by
  /// the prompt at the moment the server asks for it, and forgotten through
  /// [setPassword] with `null` — so nothing in this method can clobber it, and
  /// the edit screen never has to be handed the secret in the first place.
  Future<void> updateDevice(
    String deviceId, {
    required DshEndpoint endpoint,
    required String name,
    required String altBaseUrl,
  }) async {
    final existing = byId(deviceId);
    if (existing == null) return;
    _replace(existing.copyWith(
      name: name.trim().isEmpty ? existing.name : name.trim(),
      baseUrl: endpoint.baseUrl,
      kind: endpoint.kind,
      altBaseUrls: _alternatesFor(altBaseUrl, endpoint.baseUrl),
    ));
    await _persist();
  }

  Future<void> remove(String deviceId) async {
    _devices.removeWhere((device) => device.id == deviceId);
    await _secrets.writePassword(deviceId, null);
    if (_activeDeviceId == deviceId) {
      _activeDeviceId = _devices.isEmpty ? null : _devices.first.id;
    }
    await _persist();
  }

  Future<void> setActive(String? deviceId) async {
    if (deviceId != null && byId(deviceId) == null) return;
    _activeDeviceId = deviceId;
    notifyListeners();
  }

  Future<void> markConnected(String deviceId) async {
    final device = byId(deviceId);
    if (device == null) return;
    _replace(device.copyWith(lastConnectedAt: DateTime.now()));
    await _persist();
  }

  /// Forget every stored password while keeping the device list.
  Future<void> clearAllPasswords() async {
    for (var index = 0; index < _devices.length; index++) {
      final device = _devices[index];
      await _secrets.writePassword(device.id, null);
      _devices[index] = device.copyWith(hasPassword: false);
    }
    await _persist();
  }

  /// Any of a device's addresses identifies it, so scanning the Tailscale QR
  /// of a server that was added by its LAN address does not create a second
  /// entry for the same machine.
  DshDevice? _findByAddress(String baseUrl) {
    for (final device in _devices) {
      if (device.candidates.contains(baseUrl)) return device;
    }
    return null;
  }

  /// At most one alternate, never blank, and never a duplicate of the primary
  /// — a device that lists the same address twice would just probe it twice.
  static List<String> _alternatesFor(String altBaseUrl, String primary) {
    final trimmed = altBaseUrl.trim();
    if (trimmed.isEmpty || trimmed == primary) return const <String>[];
    return <String>[trimmed];
  }

  void _replace(DshDevice? device) {
    if (device == null) return;
    final index = _devices.indexWhere((entry) => entry.id == device.id);
    if (index == -1) {
      _devices.add(device);
    } else {
      _devices[index] = device;
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    notifyListeners();
    await _repository.save(_devices);
  }
}
