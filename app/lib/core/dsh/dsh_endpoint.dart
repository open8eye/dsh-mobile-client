import '../models/dsh_device.dart';

/// A parsed connection target: where to point the WebView, plus the access
/// password that was travelling with it (if any).
///
/// Three shapes reach this parser in practice:
///
/// * `http://192.168.1.5:3081` — the dsh-pocket LAN QR code. It carries no
///   password, so the user must type the 8-character PIN once.
/// * `http://192.168.1.5:3081/?token=Ab3xY9Zq` — dsh-pocket's share link,
///   and the shape this app itself re-uses for automatic re-login.
/// * `https://something.trycloudflare.com` — the public tunnel QR code.
///
/// The parser never guesses a port: dsh-pocket falls back to 3082..3091 when
/// 3081 is taken, so a missing port would silently target the wrong listener.
class DshEndpoint {
  const DshEndpoint({
    required this.baseUrl,
    required this.kind,
    this.password,
  });

  /// Normalised origin, no trailing slash, no `token` parameter.
  final String baseUrl;

  final DshAccessKind kind;

  /// Password extracted from the scanned link, when the link carried one.
  final String? password;

  String get host => Uri.parse(baseUrl).host;

  /// Build the URL that authenticates in one hop.
  ///
  /// Both dsh-pocket and `dsh web` accept a one-time `?token=` on the root
  /// path and answer with the session cookie, so re-entering through this URL
  /// is what makes "never type the password again" possible after the server
  /// restarts.
  String authenticatedUrl(String password) {
    final uri = Uri.parse(baseUrl);
    // No `fragment:` argument: an empty fragment would be serialised as a
    // trailing '#', and omitting it already keeps the (absent) fragment.
    return uri
        .replace(
          path: uri.path.isEmpty ? '/' : uri.path,
          queryParameters: <String, String>{'token': password},
        )
        .toString();
  }

  /// The plain entry URL, used when no password is stored.
  String get plainUrl => baseUrl;

  static final RegExp _hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://');

  /// Parse a scanned or hand-typed address.
  ///
  /// Returns `null` when the input cannot possibly be a DSH entry point, so
  /// callers can show one clear error instead of opening a broken WebView.
  static DshEndpoint? tryParse(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    // QR payloads sometimes arrive with surrounding whitespace or quotes.
    text = text.replaceAll(RegExp(r'^[\s"\x27]+|[\s"\x27]+$'), '');
    if (text.isEmpty) return null;

    // A URL never contains whitespace; `Uri.parse` is lenient enough to
    // accept "not a url" and report the host "not", which would become a
    // bogus device entry.
    if (RegExp(r'\s').hasMatch(text)) return null;

    if (!_hasScheme.hasMatch(text)) text = 'http://$text';

    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      return null;
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (uri.host.isEmpty) return null;

    // `token` is the parameter both dsh-pocket and dsh web use. The others are
    // accepted defensively because people paste hand-made links.
    String? password;
    for (final key in const <String>['token', 'pin', 'password']) {
      final value = uri.queryParameters[key];
      if (value != null && value.trim().isNotEmpty) {
        password = value.trim();
        break;
      }
    }

    // Rebuild from the parts instead of `uri.replace(query: '', fragment: '')`:
    // Dart serialises an *empty* query and fragment as '?' and '#', which
    // turned every parsed address into "http://host:3081?#".
    final base = Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    );
    var baseUrl = base.toString();
    while (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    if (baseUrl.isEmpty) return null;

    return DshEndpoint(
      baseUrl: baseUrl,
      kind: classifyHost(uri.host),
      password: password,
    );
  }

  /// Mirror of dsh-pocket's own `classifyHost`, so the badge the user sees
  /// matches the password the server will demand.
  static DshAccessKind classifyHost(String host) {
    final name = host.toLowerCase();
    if (name == 'localhost' || name == '::1' || name.startsWith('127.')) {
      return DshAccessKind.custom;
    }
    // RFC1918 private ranges + CGNAT 100.64/10 (Tailscale / ZeroTier).
    if (RegExp(r'^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)').hasMatch(name)) {
      return DshAccessKind.lan;
    }
    if (RegExp(r'^100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.').hasMatch(name)) {
      return DshAccessKind.tailscale;
    }
    if (name.endsWith('.local') || !name.contains('.')) return DshAccessKind.lan;
    if (name.endsWith('trycloudflare.com')) return DshAccessKind.tunnel;
    return DshAccessKind.tunnel;
  }
}
