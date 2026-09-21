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

  /// Android will not install it over this app: the two are signed by
  /// different keys, so the user has to uninstall first.
  signatureMismatch,

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
  String? _savedApkName;
  bool _autoCheckDone = false;

  UpdatePhase get phase => _phase;
  ReleaseInfo? get release => _release;
  String get currentVersion => _currentVersion;
  String? get error => _error;

  /// 0..1 while downloading, or `null` when the server sent no length.
  double? get progress => _progress;
  File? get downloadedFile => _downloaded;

  /// The name the APK was copied to in the phone's Downloads folder, when a
  /// copy could be kept there. That copy outlives an uninstall; the one in
  /// our cache does not.
  String? get savedApkName => _savedApkName;

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
    _savedApkName = null;
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
      await _handToInstaller(file);
    } on UpdateException catch (error) {
      _error = error.message;
      _phase = UpdatePhase.error;
    } on Exception catch (error) {
      _error = error.toString();
      _phase = UpdatePhase.error;
    }
    notifyListeners();
  }

  /// Hand the downloaded file to Android, unless it can only end in a refusal.
  ///
  /// An APK signed by a different key cannot be installed over this app, and
  /// the system's own error says nothing about the file disappearing the
  /// moment the user uninstalls to satisfy it. Checking first turns a dead end
  /// into an instruction.
  Future<void> _handToInstaller(File file) async {
    if (await AppPlatform.apkSignerMatchesInstalled(file.path) == false) {
      // Only now is a copy worth keeping, and only a public one will do:
      // Android deletes our private cache along with the app, and this is
      // the one case that ends in an uninstall. Best effort — a platform
      // that refuses costs the convenience, not the update.
      _savedApkName = await AppPlatform.exportApkToDownloads(file.path);
      _phase = UpdatePhase.signatureMismatch;
      return;
    }

    if (!await AppPlatform.canInstallPackages()) {
      // Android 8+ gates sideloading per app; the user has to grant it on a
      // system screen and come back. The downloaded file is kept.
      await AppPlatform.requestInstallPermission();
      _phase = UpdatePhase.needsPermission;
      return;
    }

    await AppPlatform.installApk(file.path);
    _phase = UpdatePhase.ready;
  }

  /// Retry the hand-off after the user granted the permission.
  Future<void> installDownloaded() async {
    final file = _downloaded;
    if (file == null) return;
    try {
      await _handToInstaller(file);
      _error = null;
    } on Exception catch (error) {
      _error = error.toString();
      _phase = UpdatePhase.error;
    }
    notifyListeners();
  }

  /// Send the downloaded APK out through the share sheet.
  ///
  /// Offered when no copy could be kept in Downloads (Android 9 and older), so
  /// the user can still put the file somewhere that survives the uninstall the
  /// system is asking for.
  Future<void> shareDownloadedApk() async {
    final file = _downloaded;
    if (file == null) return;
    await AppPlatform.shareApk(file.path);
  }

  void reset() {
    _phase = UpdatePhase.idle;
    _error = null;
    _progress = null;
    _savedApkName = null;
    notifyListeners();
  }
}
