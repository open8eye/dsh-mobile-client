import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../platform/app_platform.dart';
import '../update/release_channels.dart';
import '../update/update_service.dart';

/// Where an update check currently stands.
enum UpdatePhase {
  /// Nothing has been asked yet.
  idle,
  checking,

  /// The newest release is the one already installed.
  upToDate,

  /// A newer release exists and can be downloaded.
  available,
  downloading,

  /// The APK is on disk but Android still needs "install unknown apps".
  needsPermission,

  /// The APK has been handed to the package installer.
  ready,
  error,
}

/// Drives the update flow and exposes it to the UI.
class UpdateController extends ChangeNotifier {
  UpdateController({UpdateService? service}) : _service = service ?? UpdateService();

  final UpdateService _service;

  UpdatePhase _phase = UpdatePhase.idle;
  ReleaseInfo? _release;
  String _currentVersion = '';
  String? _error;
  double? _progress;
  File? _downloaded;
  bool _autoCheckDone = false;

  UpdatePhase get phase => _phase;
  ReleaseInfo? get release => _release;
  String get currentVersion => _currentVersion;
  String? get error => _error;

  /// 0..1 while downloading, or `null` when the server sent no length.
  double? get progress => _progress;
  File? get downloadedFile => _downloaded;

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  /// Read the installed version once, at startup.
  Future<void> loadCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
    } on Exception {
      // Without a version we cannot tell "newer" from "same"; fall back to
      // something that makes any published release look like an update.
      _currentVersion = '0.0.0';
    }
    notifyListeners();
  }

  Future<void> check({
    UpdateSourcePreference prefer = UpdateSourcePreference.auto,
  }) async {
    if (_phase == UpdatePhase.checking || _phase == UpdatePhase.downloading) return;
    _phase = UpdatePhase.checking;
    _error = null;
    _progress = null;
    notifyListeners();

    final result = await _service.check(currentVersion: _currentVersion, prefer: prefer);
    _release = result.release;
    _error = result.error;

    if (result.release == null) {
      _phase = UpdatePhase.error;
    } else if (result.updateAvailable) {
      _phase = UpdatePhase.available;
    } else {
      _phase = UpdatePhase.upToDate;
    }
    notifyListeners();
  }

  /// One silent check per launch, so a new release is noticed without the user
  /// having to go looking for it.
  Future<bool> autoCheckOnce({UpdateSourcePreference prefer = UpdateSourcePreference.auto}) async {
    if (_autoCheckDone) return false;
    _autoCheckDone = true;
    await check(prefer: prefer);
    return _phase == UpdatePhase.available;
  }

  Future<void> downloadAndInstall() async {
    final release = _release;
    if (release == null || !release.hasApk) {
      _error = 'noApk';
      _phase = UpdatePhase.error;
      notifyListeners();
      return;
    }

    _phase = UpdatePhase.downloading;
    _progress = 0;
    _error = null;
    notifyListeners();

    try {
      final directory = await getTemporaryDirectory();
      final name = release.apkName ?? 'dsh-mobile-client-${release.version.core}.apk';
      final file = File('${directory.path}/$name');
      if (await file.exists()) await file.delete();

      await _service.download(
        release,
        file,
        onProgress: (received, total) {
          if (total <= 0) return;
          _progress = received / total;
          notifyListeners();
        },
      );
      _downloaded = file;

      if (!await AppPlatform.canInstallPackages()) {
        // Android 8+ gates sideloading per app; the user has to grant it on a
        // system screen and come back. The downloaded file is kept.
        await AppPlatform.requestInstallPermission();
        _phase = UpdatePhase.needsPermission;
        notifyListeners();
        return;
      }

      await AppPlatform.installApk(file.path);
      _phase = UpdatePhase.ready;
    } on UpdateException catch (error) {
      _error = error.message;
      _phase = UpdatePhase.error;
    } on Exception catch (error) {
      _error = error.toString();
      _phase = UpdatePhase.error;
    }
    notifyListeners();
  }

  /// Retry the hand-off after the user granted the permission.
  Future<void> installDownloaded() async {
    final file = _downloaded;
    if (file == null) return;
    try {
      await AppPlatform.installApk(file.path);
      _phase = UpdatePhase.ready;
      _error = null;
    } on Exception catch (error) {
      _error = error.toString();
      _phase = UpdatePhase.error;
    }
    notifyListeners();
  }

  void reset() {
    _phase = UpdatePhase.idle;
    _error = null;
    _progress = null;
    notifyListeners();
  }
}
