import 'dart:async';
import 'dart:io';

/// How one address is tested for reachability.
///
/// Injected so the picking logic can be tested without a server.
typedef ReachabilityProbe = Future<bool> Function(Uri uri);

/// Decides which of a device's addresses a session should actually load.
///
/// One DSH server usually has more than one way in — a LAN address at home, a
/// Tailscale address everywhere else — and only the phone knows which one is
/// usable right now. Rather than making the user choose, every candidate is
/// tried at once and the first to answer wins; when both work, that also means
/// the **faster** one wins, which is the one worth having.
///
/// The probe is deliberately shallow: it stops at the response headers. DSH
/// answers the root with either the app or the login page, and both mean the
/// address is reachable. The session does the real work afterwards.
class AddressProbe {
  AddressProbe({
    ReachabilityProbe? probe,
    this.timeout = const Duration(seconds: 3),
  }) : _injected = probe;

  /// How long a single candidate gets before it is written off.
  ///
  /// Generous on purpose. A Tailscale path that is being relayed can take a
  /// second or more to answer, and writing it off early would drop the user
  /// back to an address that does not work at all.
  final Duration timeout;

  final ReachabilityProbe? _injected;

  /// The first of [baseUrls] to answer, or null when none of them does.
  ///
  /// Null is not an error to report: the caller falls back to the primary
  /// address so the WebView can show its own, far more specific failure page.
  Future<String?> firstReachable(List<String> baseUrls) async {
    if (baseUrls.isEmpty) return null;
    // The common case is one address, and probing it would only add a round
    // trip to a wait that is already the whole page load.
    if (baseUrls.length == 1) return baseUrls.first;

    final winner = Completer<String?>();
    var pending = baseUrls.length;

    void settle() {
      pending--;
      if (pending == 0 && !winner.isCompleted) winner.complete(null);
    }

    for (final baseUrl in baseUrls) {
      final uri = Uri.tryParse(baseUrl);
      if (uri == null || !uri.hasScheme) {
        // A malformed entry must not hold up the ones that are fine.
        settle();
        continue;
      }
      _probe(uri).then((reachable) {
        if (reachable && !winner.isCompleted) winner.complete(baseUrl);
      }).whenComplete(settle);
    }
    return winner.future;
  }

  Future<bool> _probe(Uri uri) => _injected?.call(uri) ?? _httpProbe(uri);

  Future<bool> _httpProbe(Uri uri) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      // The headers are the answer; the body belongs to the session that
      // follows. Draining it keeps the connection from being reset, but a
      // failure to drain changes nothing.
      unawaited(response.drain<void>().catchError((Object _) {}));
      return response.statusCode > 0;
    } on Exception {
      return false;
    } finally {
      // Also cancels the other end of any drain still in flight.
      client.close(force: true);
    }
  }
}
