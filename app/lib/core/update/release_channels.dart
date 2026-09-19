/// Which host a release was found on.
enum ReleaseSource {
  github,
  gitee;

  /// Human-readable name, used in the UI.
  String get label => this == ReleaseSource.github ? 'GitHub' : 'Gitee';
}

/// Where the updater is allowed to look.
enum UpdateSourcePreference {
  /// Ask both and take the newest, so a blocked or rate-limited host does not
  /// hide an update.
  auto,
  github,
  gitee,
}

/// Repository coordinates for the two release hosts.
///
/// Both default to the same owner/name; override them at build time when you
/// publish under a different account:
///
/// ```
/// flutter build apk --release \
///   --dart-define=DSH_GITHUB_REPO=you/dsh-mobile-client \
///   --dart-define=DSH_GITEE_REPO=you/dsh-mobile-client
/// ```
///
/// The updater reads GitHub's and Gitee's public release APIs, so a public
/// repository is required — a private one would answer 404 without a token,
/// and shipping a token inside the app is not an option.
abstract final class ReleaseChannels {
  static const String githubRepo =
      String.fromEnvironment('DSH_GITHUB_REPO', defaultValue: 'lulendi/dsh-mobile-client');

  static const String giteeRepo =
      String.fromEnvironment('DSH_GITEE_REPO', defaultValue: 'lulendi/dsh-mobile-client');

  static const String githubReleasesPage = 'https://github.com/$githubRepo/releases';
  static const String giteeReleasesPage = 'https://gitee.com/$giteeRepo/releases';
}
