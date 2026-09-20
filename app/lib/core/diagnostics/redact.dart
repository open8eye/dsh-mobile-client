/// Removes secrets from anything that leaves the app.
///
/// Two things must never reach a screenshot, a clipboard or a bug report: the
/// dsh-pocket access PIN and the session cookie. The PIN travels in the query
/// string (`/?token=<pin>`), which is precisely the URL this whole app is built
/// around — so redaction cannot be an afterthought bolted on at the UI.
///
/// Two independent passes run, because either alone is insufficient:
///
/// 1. **Known secrets.** The stored PIN may appear outside a URL — in a header,
///    in a JS error message, inside a page title. Replacing the literal value
///    is the only thing that catches those.
/// 2. **Secret-shaped parameters.** A URL the user pastes, or one the WebView
///    reports before the PIN is registered, still has to be scrubbed. Matching
///    the parameter name works without knowing the value.
abstract final class Redact {
  /// What a scrubbed value is replaced with.
  static const String placeholder = '<hidden>';

  /// Parameter names that carry credentials in this ecosystem.
  static const String _names = 'token|pin|password|passwd|pwd|secret|key|access_token';

  static final RegExp _query = RegExp(
    '([?&](?:$_names)=)[^&#\\s]*',
    caseSensitive: false,
  );

  static final RegExp _header = RegExp(
    '((?:authorization|proxy-authorization|x-api-key)\\s*:\\s*)([^\\n]*)',
    caseSensitive: false,
  );

  static final RegExp _cookie = RegExp(
    '((?:set-)?cookie\\s*:\\s*)([^\\n]*)',
    caseSensitive: false,
  );

  /// Scrub [input] using both passes.
  ///
  /// [secrets] are literal values to erase wherever they appear. Values shorter
  /// than four characters are skipped: replacing them would shred the log
  /// without meaningfully protecting anything, and a PIN that short is still
  /// caught by name in pass 2.
  static String text(String input, {Iterable<String> secrets = const <String>[]}) {
    var out = input;
    for (final secret in secrets) {
      if (secret.length < 4) continue;
      out = out.replaceAll(secret, placeholder);
    }
    out = out.replaceAllMapped(_query, (match) => '${match[1]}$placeholder');
    out = out.replaceAllMapped(_header, (match) => '${match[1]}$placeholder');
    out = out.replaceAllMapped(_cookie, (match) => '${match[1]}$placeholder');
    return out;
  }

  /// Convenience alias for the common case.
  static String url(String input, {Iterable<String> secrets = const <String>[]}) =>
      text(input, secrets: secrets);
}
