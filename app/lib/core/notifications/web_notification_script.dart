/// JavaScript injected at document start into every DSH page.
///
/// Android's WebView does not implement the Web Notifications API at all, so a
/// page calling `new Notification(...)` would throw or silently do nothing.
/// This shim replaces `window.Notification` with one that forwards to the app
/// over the flutter_inappwebview handler channel, which is what turns a DSH
/// notification into a real phone notification.
///
/// The script is idempotent: DSH navigations re-inject it on every document,
/// and the guard keeps a single bridge instance per page.
class WebNotificationScript {
  const WebNotificationScript._();

  /// Name of the Dart-side JavaScript handler.
  static const String handlerName = 'dshNotify';

  static const String source = r"""
(function () {
  if (window.__dshMobileBridge && window.__dshMobileBridge.installed) return;

  function post(title, body, tag) {
    try {
      window.flutter_inappwebview.callHandler('dshNotify', {
        title: String(title == null ? '' : title),
        body: String(body == null ? '' : body),
        tag: String(tag == null ? '' : tag)
      });
    } catch (error) {
      /* The bridge is absent on very early documents; dropping is correct. */
    }
  }

  window.__dshMobileBridge = { installed: true, post: post };
  window.__dshMobileNotify = post;

  function DshNotification(title, options) {
    options = options || {};
    post(title, options.body || '', options.tag || '');
    this.title = title == null ? '' : String(title);
    this.body = options.body || '';
    this.tag = options.tag || '';
    this.onclick = null;
    this.onclose = null;
    this.onerror = null;
    this.onshow = null;
    this.close = function () {};
    this.addEventListener = function () {};
    this.removeEventListener = function () {};
  }
  DshNotification.permission = 'granted';
  DshNotification.maxActions = 0;
  DshNotification.requestPermission = function (callback) {
    if (typeof callback === 'function') { try { callback('granted'); } catch (error) {} }
    return Promise.resolve('granted');
  };

  try {
    Object.defineProperty(window, 'Notification', {
      configurable: true,
      writable: true,
      value: DshNotification
    });
  } catch (error) {
    try { window.Notification = DshNotification; } catch (ignored) {}
  }

  // Second signal: DSH flags a finished turn by changing document.title while
  // the page is in the background. Forwarding that covers builds whose
  // notification path we do not recognise.
  try {
    var lastTitle = document.title;
    var observer = new MutationObserver(function () {
      var current = document.title;
      if (current === lastTitle) return;
      var previous = lastTitle;
      lastTitle = current;
      if (!current || current === previous) return;
      if (document.visibilityState === 'visible') return;
      post(current, '', 'title');
    });
    var target = document.querySelector('title') || document.documentElement;
    observer.observe(target, { subtree: true, childList: true, characterData: true });
  } catch (error) {
    /* MutationObserver is always available; keep the shim resilient anyway. */
  }
})();
""";

  /// Returns whether the DSH Pocket login form is on screen.
  ///
  /// Used after every load to detect that the stored password was rejected
  /// (the server rotates the session when `dsh web` restarts), so the app can
  /// sign in again instead of showing the user a web form.
  static const String probeLoginForm = r"""
(function () {
  var input = document.querySelector('input[name="token"]');
  var form = document.querySelector('form[action*="pocket-login"]');
  return (input !== null || form !== null) ? 'login' : 'ok';
})();
""";

  /// Reads the page title so the WebView tab can show what the session is doing.
  static const String readTitle = 'document.title;';
}
