/// JavaScript injected into every DSH page.
///
/// A white screen is the worst kind of failure: the page loaded, so the WebView
/// reports success, and the user sees nothing. Whatever went wrong happened
/// inside JavaScript where Dart cannot see it. These hooks drag that back out.
abstract final class DiagnosticsScript {
  /// Handler the page calls back into Dart on.
  static const String handlerName = 'dshDiag';

  /// Installed at document start, before the page's own bundles run.
  ///
  /// `console.error` is wrapped rather than replaced: the page keeps its own
  /// behaviour, we just get a copy.
  static const String source = r'''
(function () {
  if (window.__dshDiagInstalled) { return; }
  window.__dshDiagInstalled = true;

  // The bridge object is injected around document start and may not exist yet
  // when this runs. Buffer instead of dropping: the earliest messages — the
  // ones from the page's own bootstrap — are exactly the ones worth having.
  var pending = [];
  var ready = false;
  var attempts = 0;

  function pump() {
    var bridge = window.flutter_inappwebview;
    if (!bridge || !bridge.callHandler) { return; }
    ready = true;
    while (pending.length) {
      try { bridge.callHandler('dshDiag', pending.shift()); } catch (e) { /* ignore */ }
    }
  }

  var pumpTimer = setInterval(function () {
    pump();
    attempts++;
    if (ready || attempts > 100) { clearInterval(pumpTimer); }
  }, 100);

  function send(level, message) {
    if (pending.length > 300) { pending.shift(); }
    pending.push({ level: level, message: String(message).slice(0, 900) });
    if (ready) { pump(); }
  }

  function describe(value) {
    try {
      if (value === null) { return 'null'; }
      if (value === undefined) { return 'undefined'; }
      if (typeof value === 'string') { return value; }
      if (value && value.stack) { return value.stack; }
      if (typeof value === 'object') { return JSON.stringify(value); }
      return String(value);
    } catch (e) { return '[unserialisable]'; }
  }

  window.addEventListener('error', function (event) {
    var target = event.target;
    if (target && target !== window && target.tagName) {
      send('warn', 'resource failed: ' + target.tagName + ' ' +
        (target.src || target.href || ''));
      return;
    }
    send('error', 'uncaught: ' + describe(event.message) +
      ' @ ' + (event.filename || '?') + ':' + (event.lineno || 0) + ':' + (event.colno || 0));
  }, true);

  window.addEventListener('unhandledrejection', function (event) {
    send('error', 'unhandled rejection: ' + describe(event.reason));
  });

  var originalError = console.error;
  var originalWarn = console.warn;
  console.error = function () {
    send('error', Array.prototype.map.call(arguments, describe).join(' '));
    return originalError.apply(console, arguments);
  };
  console.warn = function () {
    send('warn', Array.prototype.map.call(arguments, describe).join(' '));
    return originalWarn.apply(console, arguments);
  };

  send('info', 'diagnostics hook installed');
  send('info', 'origin=' + location.origin + ' secureContext=' + window.isSecureContext);
  send('info', 'userAgent=' + navigator.userAgent);

  // Page-behaviour scripts run long after this hook, so they need a way back
  // into the same buffered channel rather than one of their own.
  window.__dshLog = send;

  // The compatibility shims run first and park their findings here, because
  // this hook is what owns the retry queue that can actually deliver them.
  try {
    var compat = window.__dshCompatReport;
    if (compat && compat.length) {
      for (var i = 0; i < compat.length; i++) { send('info', 'compat: ' + compat[i]); }
    }
  } catch (e) { /* not fatal */ }
})();
''';

  /// Answers "did anything actually render?" after the page settles.
  ///
  /// The interesting case is a body with no text and an empty mount point: the
  /// document loaded, the framework never mounted. That is what a white screen
  /// *is*, and it is worth telling the user apart from a blank page.
  static const String probeSource = r'''
(function () {
  try {
    var body = document.body;
    if (!body) { return JSON.stringify({ state: 'no-body' }); }
    var mount = document.getElementById('root') || document.getElementById('app') ||
      document.querySelector('[data-reactroot]');
    var text = (body.innerText || '').replace(/\s+/g, ' ').trim();
    return JSON.stringify({
      state: 'ok',
      readyState: document.readyState,
      textLength: text.length,
      textHead: text.slice(0, 160),
      mountFound: !!mount,
      mountChildren: mount ? mount.children.length : -1,
      scripts: document.scripts.length,
      title: document.title || '',
      bodyChildren: body.children.length
    });
  } catch (e) {
    return JSON.stringify({ state: 'probe-failed', message: String(e) });
  }
})();
''';

  /// Human-readable summary of a probe result, for the error screen and the log.
  static String describeProbe(Map<String, Object?> probe) {
    final state = probe['state'];
    if (state != 'ok') return 'page probe: $state';
    return 'page probe: text=${probe['textLength']} '
        'bodyChildren=${probe['bodyChildren']} '
        'mount=${probe['mountFound']}/${probe['mountChildren']} '
        'scripts=${probe['scripts']} ready=${probe['readyState']}';
  }

  /// True when the document loaded but nothing was painted into it.
  static bool looksBlank(Map<String, Object?> probe) {
    if (probe['state'] != 'ok') return false;
    final text = probe['textLength'];
    final bodyChildren = probe['bodyChildren'];
    if (text is! int || bodyChildren is! int) return false;
    return text == 0 && bodyChildren <= 1;
  }

  /// The one line `dsh web` answers a request with when the browser session it
  /// was given is gone. No HTML, no scripts — 67 characters of plain text.
  ///
  /// Mirrors `writeUnauthorized` in `@deepseek-ai/dsh-client-connection`.
  static const String dshWebAuthRequired = 'dsh web authentication required';

  /// True when the page is `dsh web`'s own "session rejected" body.
  ///
  /// Worth telling apart from every other bad page, because it is the one case
  /// the app can repair by itself. `dsh-pocket` never produces this text: a
  /// rejected access PIN gets the proxy's login page (HTTP 200, with a form),
  /// and a computer that is off gets a connection error. So this text means the
  /// phone *did* authenticate and the session cookie it is carrying was signed
  /// by a **previous** `dsh web` process — every restart mints a new secret.
  /// The proxy only re-runs the launch-token handshake while a request carries
  /// no `dsh-auth-*` cookie, so that stale cookie locks the phone out until it
  /// is dropped.
  static bool isDshWebAuthRejection(Map<String, Object?>? probe) {
    if (probe == null || probe['state'] != 'ok') return false;
    final head = probe['textHead'];
    return head is String && head.contains(dshWebAuthRequired);
  }
}
