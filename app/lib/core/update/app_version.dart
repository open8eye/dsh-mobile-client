/// A parsed semantic version, which is all the updater needs: "is the release
/// newer than what is installed".
///
/// Accepts the shapes actually seen in tags and `pubspec.yaml`:
/// `1.0.0`, `v1.0.0`, `1.0.0+1` (build metadata is ignored) and
/// `1.1.0-beta.1` (a pre-release sorts below the release it leads to).
class AppVersion implements Comparable<AppVersion> {
  const AppVersion._(this.parts, this.preRelease, this.raw);

  /// Numeric components, most significant first.
  final List<int> parts;

  /// Everything after the first `-`, or `null` for a final release.
  final String? preRelease;

  /// The original text, for display.
  final String raw;

  static final RegExp _pattern = RegExp(
    r'^[vV]?(\d+(?:\.\d+)*)(?:-([0-9A-Za-z.\-]+))?(?:\+.*)?$',
  );

  static AppVersion? tryParse(String? input) {
    if (input == null) return null;
    final text = input.trim();
    final match = _pattern.firstMatch(text);
    if (match == null) return null;
    final parts = match.group(1)!.split('.').map(int.parse).toList();
    return AppVersion._(parts, match.group(2), text);
  }

  /// The dotted core, without any `v` prefix or metadata: `1.2.3`.
  String get core => parts.join('.');

  @override
  int compareTo(AppVersion other) {
    final length = parts.length > other.parts.length ? parts.length : other.parts.length;
    for (var i = 0; i < length; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    // 1.0.0 is newer than 1.0.0-beta, which is newer than 1.0.0-alpha.
    if (preRelease == null && other.preRelease != null) return 1;
    if (preRelease != null && other.preRelease == null) return -1;
    if (preRelease != null && other.preRelease != null) {
      return preRelease!.compareTo(other.preRelease!);
    }
    return 0;
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) => other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hashAll(parts) ^ (preRelease?.hashCode ?? 0);

  @override
  String toString() => raw;
}
