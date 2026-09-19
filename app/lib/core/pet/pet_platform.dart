import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the Android floating-companion service.
///
/// A companion that floats over the launcher cannot be drawn by Flutter alone:
/// it needs `SYSTEM_ALERT_WINDOW` plus a foreground service, which is why the
/// Android side owns the window and this class only drives it.
///
/// iOS has no equivalent capability — a third-party app cannot draw over the
/// system UI — so every method degrades to "unsupported" there instead of
/// pretending. The in-app companion (see the Companion settings preview) is the
/// iOS fallback.
class PetPlatform {
  PetPlatform({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.dshmobile.dsh_mobile_client/pet');

  final MethodChannel _channel;

  /// Whether this platform can float a companion over other apps.
  Future<bool> isSupported() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> hasOverlayPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the system "display over other apps" screen.
  ///
  /// Returns `true` when the permission is already granted; the user has to
  /// come back to the app after granting it, so callers should re-check.
  Future<bool> requestOverlayPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestOverlayPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> isVisible() async {
    try {
      return await _channel.invokeMethod<bool>('isVisible') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Show or hide the companion.
  ///
  /// [imagePath] points at a user-chosen character image; `null` uses the
  /// built-in character drawn by the service.
  Future<bool> show({
    required double scale,
    required double opacity,
    String? imagePath,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('show', <String, Object?>{
        'scale': scale,
        'opacity': opacity,
        'imagePath': imagePath,
      }) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> hide() async {
    try {
      await _channel.invokeMethod<void>('hide');
    } on PlatformException {
      // Nothing actionable: the service is already gone.
    } on MissingPluginException {
      // Not running on Android.
    }
  }
}
