import 'package:dsh_mobile_client/core/update/app_version.dart';
import 'package:dsh_mobile_client/core/update/release_channels.dart';
import 'package:dsh_mobile_client/core/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppVersion', () {
    test('accepts the shapes that appear in tags and pubspec', () {
      expect(AppVersion.tryParse('1.2.3')?.core, '1.2.3');
      expect(AppVersion.tryParse('v1.2.3')?.core, '1.2.3');
      expect(AppVersion.tryParse('V1.2.3')?.core, '1.2.3');
      expect(AppVersion.tryParse(' 1.2.3 ')?.core, '1.2.3');
      // Build metadata is not part of the ordering.
      expect(AppVersion.tryParse('1.2.3+7')?.core, '1.2.3');
      expect(AppVersion.tryParse('1.2.3-beta.1')?.preRelease, 'beta.1');
    });

    test('rejects things that are not versions', () {
      expect(AppVersion.tryParse(null), isNull);
      expect(AppVersion.tryParse(''), isNull);
      expect(AppVersion.tryParse('latest'), isNull);
      expect(AppVersion.tryParse('v'), isNull);
    });

    test('orders numerically, not as strings', () {
      // The bug this guards against: "1.10.0" < "1.9.0" when compared as text.
      expect(AppVersion.tryParse('1.10.0')! > AppVersion.tryParse('1.9.0')!, isTrue);
      expect(AppVersion.tryParse('1.0.10')! > AppVersion.tryParse('1.0.9')!, isTrue);
      expect(AppVersion.tryParse('2.0.0')! > AppVersion.tryParse('1.99.99')!, isTrue);
    });

    test('treats a missing component as zero', () {
      expect(AppVersion.tryParse('1.2'), AppVersion.tryParse('1.2.0'));
      expect(AppVersion.tryParse('1.2.1')! > AppVersion.tryParse('1.2')!, isTrue);
    });

    test('sorts a pre-release below the release it leads to', () {
      final beta = AppVersion.tryParse('1.1.0-beta.1')!;
      final finalRelease = AppVersion.tryParse('1.1.0')!;
      expect(finalRelease > beta, isTrue);
      expect(beta > AppVersion.tryParse('1.0.0')!, isTrue);
    });

    test('equality follows the comparison, not the text', () {
      expect(AppVersion.tryParse('v1.2.0'), AppVersion.tryParse('1.2.0'));
      expect(AppVersion.tryParse('v1.2.0')!.hashCode, AppVersion.tryParse('1.2.0')!.hashCode);
    });
  });

  group('UpdateService.parseRelease', () {
    Map<String, Object?> githubPayload({List<Object?>? assets}) => <String, Object?>{
          'tag_name': 'v1.1.0',
          'body': '  ## 修复\n- 免密登录更稳  ',
          'published_at': '2025-01-02T03:04:05Z',
          'assets': assets ??
              <Object?>[
                <String, Object?>{
                  'name': 'dsh-mobile-client-1.1.0.apk',
                  'browser_download_url': 'https://example.com/app.apk',
                },
              ],
        };

    test('reads a GitHub release', () {
      final release = UpdateService.parseRelease(githubPayload(), ReleaseSource.github)!;
      expect(release.version.core, '1.1.0');
      expect(release.source, ReleaseSource.github);
      expect(release.notes, '## 修复\n- 免密登录更稳');
      expect(release.apkUrl.toString(), 'https://example.com/app.apk');
      expect(release.publishedAt?.year, 2025);
      expect(release.hasApk, isTrue);
    });

    test('reads a Gitee release, which uses created_at', () {
      final release = UpdateService.parseRelease(
        <String, Object?>{
          'tag_name': 'v1.1.0',
          'body': 'notes',
          'created_at': '2025-01-02T03:04:05Z',
          'assets': <Object?>[
            <String, Object?>{
              'name': 'app-release.apk',
              'browser_download_url': 'https://gitee.com/x/y/attach_files/1/download/app.apk',
            },
          ],
        },
        ReleaseSource.gitee,
      )!;
      expect(release.version.core, '1.1.0');
      expect(release.source, ReleaseSource.gitee);
      expect(release.publishedAt?.year, 2025);
      expect(release.hasApk, isTrue);
    });

    test('prefers a universal build over a single-ABI one', () {
      final release = UpdateService.parseRelease(
        githubPayload(
          assets: <Object?>[
            <String, Object?>{
              'name': 'app-arm64-v8a.apk',
              'browser_download_url': 'https://example.com/arm64.apk',
            },
            <String, Object?>{
              'name': 'app-universal.apk',
              'browser_download_url': 'https://example.com/universal.apk',
            },
          ],
        ),
        ReleaseSource.github,
      )!;
      expect(release.apkUrl.toString(), 'https://example.com/universal.apk');
    });

    test('reports a release that carries no APK instead of failing', () {
      final release =
          UpdateService.parseRelease(githubPayload(assets: <Object?>[]), ReleaseSource.github)!;
      expect(release.hasApk, isFalse);
      expect(release.apkUrl, isNull);
    });

    test('ignores a release whose tag is not a version', () {
      final release = UpdateService.parseRelease(
        <String, Object?>{'tag_name': 'nightly', 'body': 'x'},
        ReleaseSource.github,
      );
      expect(release, isNull);
    });

    test('treats an empty body as no notes', () {
      final release = UpdateService.parseRelease(
        <String, Object?>{'tag_name': 'v1.0.0', 'body': '   '},
        ReleaseSource.github,
      )!;
      expect(release.notes, isNull);
    });
  });

  group('release channels', () {
    test('default to the project repository on both hosts', () {
      expect(ReleaseChannels.githubRepo, isNotEmpty);
      expect(ReleaseChannels.giteeRepo, isNotEmpty);
      expect(ReleaseChannels.githubReleasesPage, contains('github.com'));
      expect(ReleaseChannels.giteeReleasesPage, contains('gitee.com'));
    });
  });
}
