import 'package:flutter/services.dart';

/// Native helpers that are too small to justify a plugin dependency.
///
/// `permission_handler` would cover the settings jump, but its Android
/// implementation currently requires AGP 9 while Flutter 3.35 ships AGP 8.9.
/// One MethodChannel is cheaper than that version conflict.
class AppPlatform {
  const AppPlatform._();

  static const MethodChannel _channel = MethodChannel('com.dshmobile.dsh_mobile_client/app');

  /// Open this app's page in system settings.
  ///
  /// This is the only way out once the user has permanently denied the camera:
  /// the system dialog will not appear a second time.
  static Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } on PlatformException {
      // The platform refused; there is nothing else to try.
    } on MissingPluginException {
      // Not implemented on this platform.
    }
  }

  /// Whether the OS will let this app hand an APK to the package installer.
  ///
  /// Always true below Android 8, where the concept does not exist.
  static Future<bool> canInstallPackages() async {
    try {
      return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // iOS never installs an APK.
      return false;
    }
  }

  /// Send the user to the "install unknown apps" screen for this app.
  static Future<void> requestInstallPermission() async {
    try {
      await _channel.invokeMethod<void>('requestInstallPermission');
    } on PlatformException {
      // Nothing else to try.
    } on MissingPluginException {
      // Not implemented on this platform.
    }
  }

  /// Hand a downloaded APK to the system package installer.
  ///
  /// Throws [PlatformException] when the file is missing or the OS refuses,
  /// so the caller can show the reason instead of failing silently.
  static Future<void> installApk(String path) async {
    await _channel.invokeMethod<void>('installApk', <String, Object?>{'path': path});
  }
}
