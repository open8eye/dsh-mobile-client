import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Raised when a password could not be written to the platform keystore.
///
/// This is deliberately a hard failure rather than a silent fallback: writing
/// the password to plain preferences would be worse than losing it, because the
/// user would never learn their access password is sitting in cleartext.
class SecretStoreException implements Exception {
  const SecretStoreException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'SecretStoreException: $message';
}

/// Stores one access password per device in the OS keystore.
///
/// Android uses the hardware-backed Keystore via flutter_secure_storage's
/// AES-GCM path; iOS uses the Keychain. Nothing here ever touches disk in
/// cleartext.
class SecretStore {
  SecretStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  final FlutterSecureStorage _storage;

  static String _key(String deviceId) => 'device_password_$deviceId';

  Future<String?> readPassword(String deviceId) async {
    try {
      final value = await _storage.read(key: _key(deviceId));
      if (value == null || value.isEmpty) return null;
      return value;
    } on Exception {
      return null;
    }
  }

  /// Persist [password]; pass `null` or an empty string to forget it.
  ///
  /// Throws [SecretStoreException] when the keystore rejects the write so the
  /// caller can tell the user instead of pretending the password was saved.
  Future<void> writePassword(String deviceId, String? password) async {
    final key = _key(deviceId);
    if (password == null || password.isEmpty) {
      try {
        await _storage.delete(key: key);
      } on Exception catch (error) {
        throw SecretStoreException('无法从系统密钥库删除访问密码', error);
      }
      return;
    }
    try {
      await _storage.write(key: key, value: password);
    } on Exception catch (error) {
      throw SecretStoreException('无法把访问密码写入系统密钥库', error);
    }
  }

  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
    } on Exception {
      // Best effort: a failed wipe must not block the caller.
    }
  }
}
