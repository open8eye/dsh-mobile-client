/// Compatibility shims injected before the DSH bundle runs.
///
/// The DSH web frontend is built by Vite for a modern browser. Vite transpiles
/// *syntax* down to its target, but it does **not** polyfill *runtime* APIs, and
/// the bundle uses several that are newer than the ES2020 baseline:
///
/// | API | Needs |
/// |---|---|
/// | `Object.hasOwn` | Chromium 93 |
/// | `Array.prototype.at` | Chromium 92 |
/// | `String.prototype.replaceAll` | Chromium 85 |
///
/// `Object.hasOwn` is the one that matters: every call site is inside the
/// dependency-injection container that bootstraps the app. On a WebView older
/// than Chromium 93 it is `undefined`, the container throws while wiring
/// itself up, React never mounts, and the user gets a white screen with no
/// error and no clue. That is exactly the failure seen on an Android 10 /
/// MIUI 12 device while a current phone with a current WebView was fine.
///
/// `crypto.randomUUID` is a different trap and is shimmed for the opposite
/// reason: it is gated behind a *secure context*, and this app deliberately
/// talks to a LAN address over plain HTTP. On a modern WebView the method is
/// therefore still missing — not because the engine is old, but because the
/// origin is not trusted. `crypto.getRandomValues` has no such restriction, so
/// the shim is straightforward.
///
/// Every shim checks for the native implementation first, so a current WebView
/// is left untouched. Each one also reports whether it was needed, which turns
/// the bug report into a direct answer instead of a guess.
abstract final class CompatScript {
  /// Handler the shim reports its findings on.
  static const String handlerName = 'dshDiag';

  static const String source = r'''
(function () {
  if (window.__dshCompatInstalled) { return; }
  window.__dshCompatInstalled = true;

  var applied = [];
  var native = [];

  // This script runs before anything else, which is the point — but it also
  // means the Flutter bridge does not exist yet and a message sent now would be
  // lost. The findings are parked on a global instead, and the diagnostics hook
  // (installed immediately after, with a retry queue) forwards them.
  function report(message) {
    try {
      window.__dshCompatReport = (window.__dshCompatReport || []).concat([message]);
    } catch (e) { /* never break the page over a log line */ }
  }

  function define(target, name, implementation) {
    try {
      Object.defineProperty(target, name, {
        value: implementation,
        writable: true,
        configurable: true
      });
      return true;
    } catch (e) { return false; }
  }

  // --- Object.hasOwn: Chromium 93 -------------------------------------------
  if (typeof Object.hasOwn === 'function') {
    native.push('Object.hasOwn');
  } else if (define(Object, 'hasOwn', function hasOwn(object, property) {
    if (object === null || object === undefined) {
      throw new TypeError('Cannot convert undefined or null to object');
    }
    return Object.prototype.hasOwnProperty.call(Object(object), property);
  })) {
    applied.push('Object.hasOwn');
  }

  // --- Array.prototype.at / String.prototype.at: Chromium 92 ---------------
  function atImplementation(index) {
    var length = this.length >>> 0;
    var relative = Number(index) || 0;
    var position = relative >= 0 ? relative : length + relative;
    if (position < 0 || position >= length) { return undefined; }
    return this[position];
  }
  if (typeof Array.prototype.at === 'function') {
    native.push('Array.prototype.at');
  } else if (define(Array.prototype, 'at', atImplementation)) {
    applied.push('Array.prototype.at');
  }
  if (typeof String.prototype.at !== 'function' && define(String.prototype, 'at', atImplementation)) {
    applied.push('String.prototype.at');
  }

  // --- String.prototype.replaceAll: Chromium 85 ----------------------------
  if (typeof String.prototype.replaceAll === 'function') {
    native.push('String.prototype.replaceAll');
  } else if (define(String.prototype, 'replaceAll', function replaceAll(search, replacement) {
    if (search instanceof RegExp) {
      if (!search.global) {
        throw new TypeError('replaceAll must be called with a global RegExp');
      }
      return this.replace(search, replacement);
    }
    var source = String(this);
    var needle = String(search);
    // An empty search matches between every character, including before the
    // first and after the last: 'ab'.replaceAll('', '-') is '-a-b-', not 'a-b'.
    if (needle === '') {
      var padded = '';
      for (var i = 0; i <= source.length; i++) {
        padded += typeof replacement === 'function'
          ? replacement('', i, source)
          : String(replacement);
        if (i < source.length) { padded += source.charAt(i); }
      }
      return padded;
    }
    if (typeof replacement === 'function') {
      var out = '';
      var from = 0;
      var found = source.indexOf(needle, from);
      while (found !== -1) {
        out += source.slice(from, found) + replacement(needle, found, source);
        from = found + needle.length;
        found = source.indexOf(needle, from);
      }
      return out + source.slice(from);
    }
    return source.split(needle).join(String(replacement));
  })) {
    applied.push('String.prototype.replaceAll');
  }

  // --- crypto.randomUUID: needs a secure context, not a new engine ---------
  try {
    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID !== 'function') {
      if (define(crypto, 'randomUUID', function randomUUID() {
        var bytes = new Uint8Array(16);
        crypto.getRandomValues(bytes);
        bytes[6] = (bytes[6] & 0x0f) | 0x40;
        bytes[8] = (bytes[8] & 0x3f) | 0x80;
        var hex = [];
        for (var i = 0; i < 16; i++) {
          hex.push((bytes[i] + 0x100).toString(16).slice(1));
        }
        return hex.slice(0, 4).join('') + '-' + hex.slice(4, 6).join('') + '-' +
          hex.slice(6, 8).join('') + '-' + hex.slice(8, 10).join('') + '-' +
          hex.slice(10, 16).join('');
      })) {
        applied.push('crypto.randomUUID');
      }
    } else if (typeof crypto !== 'undefined') {
      native.push('crypto.randomUUID');
    }
  } catch (e) { /* an unwritable crypto is not fatal */ }

  if (applied.length) {
    report('SHIMMED ' + applied.join(', ') + ' (WebView too old or origin insecure)');
  }
  if (native.length) {
    report('native ' + native.join(', '));
  }
  if (!applied.length && !native.length) {
    report('nothing needed');
  }
})();
''';
}
