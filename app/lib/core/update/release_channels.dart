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
/// **The two owners are different, and that is not a typo.** The project is
/// `open8eye/…` on GitHub and `lulendi/…` on Gitee, so there is no single
/// default that fits both — each is spelled out.
///
/// Getting one wrong is quiet: the updater simply reports that host as
/// unreachable and leans on the other, which looks like a working update
/// check right up until the working host is the one that fails. That is
/// exactly what happened in 1.1.2 — both hosts were wired to `lulendi/…`,
/// so every published APK had exactly one live channel.
///
/// Override at build time if you publish elsewhere:
///
/// ```
/// flutter build apk --release \
///   --dart-define=DSH_GITHUB_REPO=you/dsh-mobile-client \
///   --dart-define=DSH_GITEE_REPO=you/dsh-mobile-client
/// ```
///
/// CI passes `github.repository` for the GitHub half, so it only gets this
/// wrong on the Gitee half — where the answer has to come from the
/// `GITEE_REPO` repository variable.
///
/// The updater reads GitHub's and Gitee's public release APIs, so a public
/// repository is required — a private one would answer 404 without a token,
/// and shipping a token inside the app is not an option.
abstract final class ReleaseChannels {
  static const String githubRepo =
      String.fromEnvironment('DSH_GITHUB_REPO', defaultValue: 'open8eye/dsh-mobile-client');

  static const String giteeRepo =
      String.fromEnvironment('DSH_GITEE_REPO', defaultValue: 'lulendi/dsh-mobile-client');

  static const String githubReleasesPage = 'https://github.com/$githubRepo/releases';
  static const String giteeReleasesPage = 'https://gitee.com/$giteeRepo/releases';
}
