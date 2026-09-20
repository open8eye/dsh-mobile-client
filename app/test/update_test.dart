import 'package:dsh_mobile_client/core/update/app_version.dart';
import 'package:dsh_mobile_client/core/update/release_channels.dart';
import 'package:dsh_mobile_client/core/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateException.isMissing', () {
    test('only a 404 counts as "nothing published"', () {
      // A 404 from a release API is an answer, not an outage: the repository
      // is missing, private, or simply has no release. Everything else is a
      // failure the user cannot fix by publishing.
      expect(const UpdateException('HTTP 404', statusCode: 404).isMissing, isTrue);
      expect(const UpdateException('HTTP 403', statusCode: 403).isMissing, isFalse);
      expect(const UpdateException('HTTP 500', statusCode: 500).isMissing, isFalse);
      expect(const UpdateException('timed out').isMissing, isFalse);
    });
  });

  group('UpdateService.describeFailure', () {
    test('every channel answering 404 becomes its own diagnosis', () {
      // This is the state a freshly published app is in, and the one the
      // user hit: both hosts answer 404 until a release exists. Showing
      // "GitHub: HTTP 404 / Gitee: HTTP 404" would not say that.
      expect(
        UpdateService.describeFailure(
          <String>['GitHub: HTTP 404', 'Gitee: HTTP 404'],
          missing: 2,
          sources: 2,
        ),
        'notPublished',
      );
    });

    test('one 404 among real failures keeps the detail', () {
      // A host that answered is not the whole story when the other timed out.
      expect(
        UpdateService.describeFailure(
          <String>['GitHub: HTTP 404', 'Gitee: SocketException'],
          missing: 1,
          sources: 2,
        ),
        'GitHub: HTTP 404\nGitee: SocketException',
      );
    });

    test('nothing found and nothing wrong is not a 404', () {
      expect(
        UpdateService.describeFailure(
          const <String>[],
          missing: 0,
          sources: 2,
        ),
        'no release found',
      );
    });
  });

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

  // The two builds are published side by side. Handing one to the other's user
  // is worse than offering no update at all, so these are the tests that stop
  // an old device from silently being sent a standard APK.
  group('UpdateService.pickApk keeps the two builds apart', () {
    List<Object?> bothBuilds() => <Object?>[
          <String, Object?>{
            'name': 'dsh-mobile-client-1.0.0.apk',
            'browser_download_url': 'https://example.com/standard.apk',
          },
          <String, Object?>{
            'name': 'dsh-mobile-client-1.0.0-legacy.apk',
            'browser_download_url': 'https://example.com/legacy.apk',
          },
        ];

    test('a standard install is never offered the legacy APK', () {
      final picked = UpdateService.pickApk(bothBuilds())!;
      expect(picked['browser_download_url'], 'https://example.com/standard.apk');
    });

    test('a legacy install is never offered the standard APK', () {
      final picked = UpdateService.pickApk(
        bothBuilds(),
        variant: BuildVariant.legacy,
      )!;
      expect(picked['browser_download_url'], 'https://example.com/legacy.apk');
    });

    test('the order the assets arrive in does not matter', () {
      // The old picker fell through to "first asset wins", so this is the case
      // that used to send a legacy user a standard APK.
      final reversed = bothBuilds().reversed.toList();
      expect(
        UpdateService.pickApk(reversed)!['browser_download_url'],
        'https://example.com/standard.apk',
      );
      expect(
        UpdateService.pickApk(reversed, variant: BuildVariant.legacy)!['browser_download_url'],
        'https://example.com/legacy.apk',
      );
    });

    test('a release with no APK for this variant yields nothing', () {
      final standardOnly = <Object?>[
        <String, Object?>{
          'name': 'dsh-mobile-client-1.0.0.apk',
          'browser_download_url': 'https://example.com/standard.apk',
        },
      ];
      expect(
        UpdateService.pickApk(standardOnly, variant: BuildVariant.legacy),
        isNull,
      );
    });

    test('an ABI hint still ranks within a variant', () {
      final legacyAbis = <Object?>[
        <String, Object?>{
          'name': 'dsh-mobile-client-1.0.0-legacy-arm64-v8a.apk',
          'browser_download_url': 'https://example.com/legacy-arm64.apk',
        },
        <String, Object?>{
          'name': 'dsh-mobile-client-1.0.0-legacy-universal.apk',
          'browser_download_url': 'https://example.com/legacy-universal.apk',
        },
      ];
      expect(
        UpdateService.pickApk(legacyAbis, variant: BuildVariant.legacy)!['browser_download_url'],
        'https://example.com/legacy-universal.apk',
      );
    });

    test('a release carrying only a legacy APK does not update a standard install', () {
      final release = UpdateService.parseRelease(
        <String, Object?>{
          'tag_name': 'v1.0.0',
          'assets': <Object?>[
            <String, Object?>{
              'name': 'dsh-mobile-client-1.0.0-legacy.apk',
              'browser_download_url': 'https://example.com/legacy.apk',
            },
          ],
        },
        ReleaseSource.github,
      )!;
      expect(release.hasApk, isFalse);
      expect(release.apkUrl, isNull);
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
