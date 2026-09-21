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

  /// Which build of the app this is: `legacy` carries its own WebView kernel,
  /// `standard` does not.
  ///
  /// The two ship as separate APKs and must never update into each other — a
  /// standard APK on an old device white-screens, and a legacy APK is a
  /// needless ~120 MB for everyone else.
  static Future<String?> buildVariant() async {
    try {
      return await _channel.invokeMethod<String>('buildVariant');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// What the Android startup hook did about the WebView kernel.
  ///
  /// Returns a human-readable sentence, or null on a platform that has no such
  /// hook (iOS). It is a report, not a control: the swap has already happened
  /// by the time Dart runs, or it never will for this process.
  static Future<String?> webViewKernel() async {
    try {
      return await _channel.invokeMethod<String>('webViewKernel');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Open the system's app-info page for [packageName], or for this app when
  /// it is null.
  ///
  /// Used to point at the system WebView: on an old device that is the
  /// component the user has to update, and its app-info page is where the
  /// store link and the version number live.
  static Future<bool> openAppInfo([String? packageName]) async {
    try {
      await _channel.invokeMethod<void>('openAppInfo', <String, Object?>{
        'package': packageName,
      });
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
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

  /// Host facts a bug report needs.
  ///
  /// The WebView package and version are the point of this call: on some OEM
  /// builds — MIUI in particular — the system WebView is missing, disabled or
  /// years out of date, and every page then renders white with no error
  /// anywhere. That is completely invisible from inside Dart.
  static Future<Map<String, String>> deviceInfo() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('deviceInfo');
      if (raw == null) return const <String, String>{};
      return <String, String>{
        for (final entry in raw.entries)
          if (entry.value != null && entry.value.toString().isNotEmpty)
            entry.key: entry.value.toString(),
      };
    } on PlatformException {
      return const <String, String>{};
    } on MissingPluginException {
      return const <String, String>{};
    }
  }

  /// Share plain text through the system share sheet.
  ///
  /// A bug report has to be able to leave the phone, and the share sheet is the
  /// one channel that always exists — no account, no server, no dependency.
  static Future<bool> shareText({required String text, required String subject}) async {
    try {
      await _channel.invokeMethod<void>('shareText', <String, Object?>{
        'text': text,
        'subject': subject,
      });
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Hand a downloaded APK to the system package installer.
  ///
  /// Throws [PlatformException] when the file is missing or the OS refuses,
  /// so the caller can show the reason instead of failing silently.
  static Future<void> installApk(String path) async {
    await _channel.invokeMethod<void>('installApk', <String, Object?>{'path': path});
  }

  /// Whether the APK at [path] is signed by the key that signed this app.
  ///
  /// Android refuses the install when it is not, and the only way out is to
  /// uninstall — which deletes the downloaded APK if it is still in our
  /// private cache. Knowing this before the hand-off is what lets the UI say
  /// where a copy that survives an uninstall can be found.
  ///
  /// `null` means "could not tell", and the caller should simply try.
  static Future<bool?> apkSignerMatchesInstalled(String path) async {
    try {
      return await _channel.invokeMethod<bool>('apkSignerMatchesInstalled', <String, Object?>{
        'path': path,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Copy the downloaded APK into the phone's public Downloads collection.
  ///
  /// Returns the name it was saved under, or null when this platform has no
  /// permission-free way to do it (Android 9 and older, iOS).
  static Future<String?> exportApkToDownloads(String path) async {
    try {
      return await _channel.invokeMethod<String>('exportApk', <String, Object?>{'path': path});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Send the APK out through the system share sheet.
  ///
  /// The escape hatch on Android 9 and older: the user can put the file
  /// somewhere that survives an uninstall before uninstalling.
  static Future<bool> shareApk(String path) async {
    try {
      await _channel.invokeMethod<void>('shareApk', <String, Object?>{'path': path});
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
