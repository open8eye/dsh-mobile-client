import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/app_platform.dart';
import 'app_version.dart';
import 'release_channels.dart';

/// Raised when an update step fails for a reason worth showing the user.
class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One release, normalised so GitHub and Gitee look the same to the UI.
@immutable
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.source,
    this.tagName,
    this.notes,
    this.apkUrl,
    this.apkName,
    this.publishedAt,
  });

  final AppVersion version;
  final ReleaseSource source;
  final String? tagName;

  /// The release body; the project's release notes are written for this field.
  final String? notes;
  final Uri? apkUrl;
  final String? apkName;
  final DateTime? publishedAt;

  bool get hasApk => apkUrl != null;
}

@immutable
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    this.release,
    this.updateAvailable = false,
    this.error,
  });

  final String currentVersion;
  final ReleaseInfo? release;
  final bool updateAvailable;

  /// Set only when no channel could be reached at all.
  final String? error;
}

/// Which artefact this installation is.
///
/// The two builds are published side by side and must never update into each
/// other — see [UpdateService.pickApk].
enum BuildVariant {
  /// The normal app: the system WebView, upgraded in-process to a newer kernel
  /// that happens to be installed.
  standard,

  /// Carries its own WebView kernel, so it works on a device with nothing
  /// newer installed.
  legacy,
}

/// Checks GitHub and Gitee for a newer release and downloads its APK.
///
/// Both hosts expose the same shape (`tag_name`, `body`, `assets[]`), so one
/// parser covers them. The public APIs need no authentication, which is why
/// this app can ship an updater at all.
class UpdateService {
  UpdateService({HttpClient? client, BuildVariant? variant})
      : _variant = variant,
        _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 12);
    _client.userAgent = 'DSH-Mobile-Client';
  }

  final HttpClient _client;

  /// Null until [_buildVariant] has asked the platform.
  BuildVariant? _variant;

  void dispose() => _client.close(force: true);

  Future<UpdateCheckResult> check({
    required String currentVersion,
    UpdateSourcePreference prefer = UpdateSourcePreference.auto,
  }) async {
    final sources = switch (prefer) {
      UpdateSourcePreference.github => const <ReleaseSource>[ReleaseSource.github],
      UpdateSourcePreference.gitee => const <ReleaseSource>[ReleaseSource.gitee],
      UpdateSourcePreference.auto => const <ReleaseSource>[
          ReleaseSource.github,
          ReleaseSource.gitee,
        ],
    };

    final errors = <String>[];
    final found = <ReleaseInfo>[];

    // Queried together: on a phone that can only reach one of the two hosts,
    // the other would otherwise add its timeout to every single check.
    await Future.wait(
      sources.map((source) async {
        try {
          final release = await _fetchLatest(source);
          if (release != null) found.add(release);
        } on UpdateException catch (error) {
          errors.add('${source.label}: ${error.message}');
        } on Exception catch (error) {
          errors.add('${source.label}: $error');
        }
      }),
    );

    if (found.isEmpty) {
      return UpdateCheckResult(
        currentVersion: currentVersion,
        error: errors.isEmpty ? 'no release found' : errors.join('\n'),
      );
    }

    found.sort((a, b) => b.version.compareTo(a.version));
    final best = found.first;
    final current = AppVersion.tryParse(currentVersion);
    return UpdateCheckResult(
      currentVersion: currentVersion,
      release: best,
      updateAvailable: current == null || best.version > current,
    );
  }

  Future<ReleaseInfo?> _fetchLatest(ReleaseSource source) async {
    final url = source == ReleaseSource.github
        ? Uri.parse('https://api.github.com/repos/${ReleaseChannels.githubRepo}/releases/latest')
        : Uri.parse('https://gitee.com/api/v5/repos/${ReleaseChannels.giteeRepo}/releases/latest');
    final json = await _getJson(url);
    if (json == null) return null;
    return parseRelease(json, source, variant: await _buildVariant());
  }

  /// Which artefact this installation should update to.
  ///
  /// Resolved once and cached. An unreadable answer means standard, which is
  /// the common case and the one that cannot break a device.
  Future<BuildVariant> _buildVariant() async {
    final cached = _variant;
    if (cached != null) return cached;
    final reported = await AppPlatform.buildVariant();
    final resolved = reported == 'legacy'
        ? BuildVariant.legacy
        : BuildVariant.standard;
    _variant = resolved;
    return resolved;
  }

  Future<Map<String, Object?>?> _getJson(Uri url) async {
    final request = await _client.getUrl(url);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw UpdateException('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw const UpdateException('unexpected response');
    }
    return decoded;
  }

  /// Normalise a release payload.
  ///
  /// GitHub's `/releases/latest` and Gitee's `/releases/latest` return the same
  /// fields for everything this app needs, so one parser covers both. Public
  /// and static so the shapes can be tested without a network.
  @visibleForTesting
  static ReleaseInfo? parseRelease(
    Map<String, Object?> json,
    ReleaseSource source, {
    BuildVariant variant = BuildVariant.standard,
  }) {
    final tag = json['tag_name'] as String?;
    final version = AppVersion.tryParse(tag);
    if (version == null) return null;

    final asset = pickApk(json['assets'], variant: variant);
    final published = json['published_at'] ?? json['created_at'];
    final notes = (json['body'] as String?)?.trim();

    return ReleaseInfo(
      version: version,
      source: source,
      tagName: tag,
      notes: notes == null || notes.isEmpty ? null : notes,
      apkUrl: asset == null ? null : Uri.tryParse(asset['browser_download_url'] as String? ?? ''),
      apkName: asset?['name'] as String?,
      publishedAt: published is String ? DateTime.tryParse(published) : null,
    );
  }

  /// Pick the APK that belongs to [variant].
  ///
  /// The legacy and standard builds are different artefacts, and updating one
  /// into the other is worse than offering no update at all: a standard APK on
  /// an old device white-screens, and a legacy APK drags a bundled Chromium
  /// down the wire for everyone who does not need it. So the two are filtered
  /// apart first, and only then ranked.
  ///
  /// Prefer a universal build, then arm64, then arm32; anything else is better
  /// than nothing. Returns null when the release has no APK for this variant,
  /// which is the honest answer rather than a wrong download.
  @visibleForTesting
  static Map<String, Object?>? pickApk(
    Object? assets, {
    BuildVariant variant = BuildVariant.standard,
  }) {
    if (assets is! List<Object?>) return null;
    final all = assets
        .whereType<Map<String, Object?>>()
        .where((asset) => (asset['name'] as String? ?? '').toLowerCase().endsWith('.apk'))
        .toList();
    if (all.isEmpty) return null;

    bool isLegacy(Map<String, Object?> asset) =>
        (asset['name'] as String? ?? '').toLowerCase().contains('legacy');

    final apks = all
        .where((asset) => isLegacy(asset) == (variant == BuildVariant.legacy))
        .toList();
    if (apks.isEmpty) return null;

    for (final hint in const <String>['universal', 'arm64', 'armeabi']) {
      for (final apk in apks) {
        if ((apk['name'] as String? ?? '').toLowerCase().contains(hint)) return apk;
      }
    }
    return apks.first;
  }

  /// Stream the release APK to [target], reporting progress when the server
  /// sends a content length.
  Future<void> download(
    ReleaseInfo release,
    File target, {
    void Function(int received, int total)? onProgress,
  }) async {
    final url = release.apkUrl;
    if (url == null) throw const UpdateException('这个版本没有附带 APK');

    final request = await _client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != 200) {
      throw UpdateException('下载失败（HTTP ${response.statusCode}）');
    }

    final total = response.contentLength;
    final sink = target.openWrite();
    var received = 0;
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }
    if (received == 0) throw const UpdateException('下载到的文件是空的');
  }
}
