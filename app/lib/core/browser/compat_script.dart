/// Compatibility shims injected before the DSH bundle runs.
///
/// The DSH web frontend is built by Vite for a modern browser. Vite transpiles
/// *syntax* down to its target, but it does **not** polyfill *runtime* APIs, and
/// the bundle uses a good number that are newer than the ES2020 baseline. Every
/// entry below was found by scanning the shipped bundles, not by guessing.
///
/// | API | Needs |
/// |---|---|
/// | `String.prototype.replaceAll` | Chromium 85 |
/// | `Array.prototype.at` / `String.prototype.at` | Chromium 92 |
/// | `crypto.randomUUID` | Chromium 92, **and a secure context** |
/// | `Object.hasOwn` | Chromium 93 |
/// | `Array.prototype.findLast` / `findLastIndex` | Chromium 97 |
/// | `AbortSignal.timeout` | Chromium 103 |
/// | `Array.prototype.toReversed` / `toSorted` / `with` | Chromium 110 |
/// | `String.prototype.toWellFormed` | Chromium 111 |
/// | `ArrayBuffer.prototype.transfer` | Chromium 114 |
/// | `AbortSignal.any` | Chromium 116 |
/// | `Object.groupBy` / `Map.groupBy` | Chromium 117 |
/// | `Promise.withResolvers` | Chromium 119 |
/// | `URL.canParse` | Chromium 120 |
/// | `Set.prototype.union` / `intersection` / `difference` | Chromium 122 |
/// | `URL.parse` | Chromium 126 |
/// | `Promise.try` | Chromium 128 |
/// | `Symbol.dispose` | Chromium 134 |
/// | `navigator.clipboard` | **a secure context** |
///
/// The three that actually broke a real device are worth naming. `Object.hasOwn`
/// sits inside the dependency-injection container that bootstraps the app: on an
/// engine without it the container throws while wiring itself up, React never
/// mounts, and the user gets a white screen with no error. `Promise.withResolvers`
/// and `AbortSignal.any` are what broke the *bundled-kernel* build — Chromium 113
/// is new enough to parse and mount, but the session controller's control stream
/// calls `AbortSignal.any` on the first read, so the app renders and then never
/// connects. That pair is why the floor here is a parse floor and not a
/// "new enough to work" floor.
///
/// `crypto.randomUUID` and `navigator.clipboard` are shimmed for the opposite
/// reason: both are gated behind a *secure context*, and this app deliberately
/// talks to a LAN address over plain HTTP. On a brand-new engine they are still
/// missing — not because the engine is old, but because the origin is not
/// trusted. `crypto.getRandomValues` and `document.execCommand('copy')` have no
/// such restriction.
///
/// Every shim checks for the native implementation first, so a current engine is
/// left untouched, and each reports whether it was needed. Anything missing that
/// is *not* shimmed here is reported by name instead, so a bug report answers the
/// question directly. `structuredClone` is deliberately in that group: a clone
/// that is subtly wrong corrupts state silently, which is worse to debug than a
/// loud "is not a function".
///
/// The behaviour of every shim here is checked against the real implementation by
/// `tools/compat_check.mjs`, which removes the native methods and compares.
abstract final class CompatScript {
  /// Handler the shim reports its findings on.
  static const String handlerName = 'dshDiag';

  /// The oldest Chromium that can even *parse* the DSH bundle.
  ///
  /// This is a syntax floor, not an API floor, and the distinction is the whole
  /// point. Vite transpiles for its configured target and stops there, so the
  /// bundle ships syntax that an older engine cannot parse at all — and a parse
  /// error means **not one line of the file runs**, which is why shims cannot
  /// rescue it however complete they are.
  ///
  /// Measured against the shipped bundle, the binding constraint is the static
  /// initialisation block:
  ///
  /// | construct | needs |
  /// |---|---|
  /// | private methods `#name() {}` | Chromium 84 |
  /// | `??=`, `||=`, `&&=` | Chromium 85 |
  /// | `static {}` blocks | Chromium 94 |
  ///
  /// A device running Chromium 83 fails on `??=` first, which is exactly the
  /// `Uncaught SyntaxError: Unexpected token '='` seen in the field. Raising
  /// this to the `static {}` floor is deliberate: patching the operators would
  /// only move the failure a few kilobytes down the same file.
  ///
  /// Rewriting the bundle to run below this is not a shim, it is a transpiler —
  /// `static {}` cannot be rewritten textually without understanding the class
  /// it sits in. Below this, the only real fix is updating the system WebView.
  static const int minimumChromium = 94;

  /// Chromium version behind a WebView build string, e.g. `83.0.4103.101`.
  ///
  /// Returns null when the string is absent or not a version, so an unknown
  /// WebView is never mistaken for an old one.
  static int? chromiumMajor(String? version) {
    if (version == null) return null;
    final match = RegExp(r'^\s*(\d+)').firstMatch(version);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  /// Whether [version] is too old to run the bundle at all.
  static bool isTooOld(String? version) {
    final major = chromiumMajor(version);
    return major != null && major < minimumChromium;
  }

  static const String source = r'''
(function () {
  if (window.__dshCompatInstalled) { return; }
  window.__dshCompatInstalled = true;

  var applied = [];
  var gaps = [];

  // This script runs before anything else, which is the point — but it also
  // means the Flutter bridge does not exist yet and a message sent now would be
  // lost. The findings are parked on a global instead, and the diagnostics hook
  // (installed immediately after, with a retry queue) forwards them.
  function report(message) {
    try {
      window.__dshCompatReport = (window.__dshCompatReport || []).concat([message]);
    } catch (e) { /* never break the page over a log line */ }
  }

  function define(target, name, value) {
    try {
      Object.defineProperty(target, name, {
        value: value,
        writable: true,
        configurable: true,
        enumerable: false
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  // Install only when the engine really lacks it, and record which happened.
  // "shimmed" versus "native" is the whole diagnostic value of this script.
  function ensure(label, has, install) {
    try {
      if (has()) { return; }
      if (install()) { applied.push(label); return; }
    } catch (e) { /* fall through to the gap list */ }
    gaps.push(label);
  }

  function slice(list) { return Array.prototype.slice.call(list); }

  // --- Object.hasOwn: Chromium 93 -------------------------------------------
  // The one that matters most: every call site is inside the dependency
  // injection container that bootstraps the app.
  ensure('Object.hasOwn',
    function () { return typeof Object.hasOwn === 'function'; },
    function () {
      return define(Object, 'hasOwn', function hasOwn(object, property) {
        if (object === null || object === undefined) {
          throw new TypeError('Cannot convert undefined or null to object');
        }
        return Object.prototype.hasOwnProperty.call(Object(object), property);
      });
    });

  // --- Array.prototype.at / String.prototype.at: Chromium 92 ----------------
  function atImplementation(index) {
    var length = this.length >>> 0;
    var relative = Number(index) || 0;
    var position = relative >= 0 ? relative : length + relative;
    if (position < 0 || position >= length) { return undefined; }
    return this[position];
  }
  ensure('Array.prototype.at',
    function () { return typeof Array.prototype.at === 'function'; },
    function () { return define(Array.prototype, 'at', atImplementation); });
  ensure('String.prototype.at',
    function () { return typeof String.prototype.at === 'function'; },
    function () { return define(String.prototype, 'at', atImplementation); });

  // --- String.prototype.replaceAll: Chromium 85 -----------------------------
  ensure('String.prototype.replaceAll',
    function () { return typeof String.prototype.replaceAll === 'function'; },
    function () {
      return define(String.prototype, 'replaceAll', function replaceAll(search, replacement) {
        if (search instanceof RegExp) {
          if (!search.global) {
            throw new TypeError('replaceAll must be called with a global RegExp');
          }
          return this.replace(search, replacement);
        }
        var source = String(this);
        var needle = String(search);
        // An empty search matches between every character, including before the
        // first and after the last: 'ab'.replaceAll('', '-') is '-a-b-'.
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
      });
    });

  // --- Promise.withResolvers: Chromium 119 ----------------------------------
  ensure('Promise.withResolvers',
    function () { return typeof Promise.withResolvers === 'function'; },
    function () {
      return define(Promise, 'withResolvers', function withResolvers() {
        var resolve, reject;
        var promise = new Promise(function (res, rej) { resolve = res; reject = rej; });
        return { promise: promise, resolve: resolve, reject: reject };
      });
    });

  // --- Promise.try: Chromium 128 --------------------------------------------
  ensure('Promise.try',
    function () { return typeof Promise.try === 'function'; },
    function () {
      return define(Promise, 'try', function promiseTry(fn) {
        var args = slice(arguments).slice(1);
        // A synchronous throw inside the executor rejects, which is what the
        // spec asks for.
        return new Promise(function (resolve) { resolve(fn.apply(undefined, args)); });
      });
    });

  // --- AbortSignal.any: Chromium 116 ----------------------------------------
  ensure('AbortSignal.any',
    function () { return typeof AbortSignal.any === 'function'; },
    function () {
      if (typeof AbortController !== 'function') { return false; }
      return define(AbortSignal, 'any', function any(signals) {
        var controller = new AbortController();
        var list = slice(signals);
        var i;
        for (i = 0; i < list.length; i++) {
          if (list[i].aborted) {
            controller.abort(list[i].reason);
            return controller.signal;
          }
        }
        for (i = 0; i < list.length; i++) {
          (function (signal) {
            signal.addEventListener('abort', function () {
              controller.abort(signal.reason);
            }, { once: true });
          })(list[i]);
        }
        return controller.signal;
      });
    });

  // --- AbortSignal.timeout: Chromium 103 ------------------------------------
  ensure('AbortSignal.timeout',
    function () { return typeof AbortSignal.timeout === 'function'; },
    function () {
      if (typeof AbortController !== 'function') { return false; }
      return define(AbortSignal, 'timeout', function timeout(ms) {
        var controller = new AbortController();
        setTimeout(function () {
          var reason;
          try {
            reason = new DOMException('The operation timed out.', 'TimeoutError');
          } catch (e) {
            reason = undefined;
          }
          controller.abort(reason);
        }, ms);
        return controller.signal;
      });
    });

  // --- Array.prototype.findLast / findLastIndex: Chromium 97 ----------------
  ensure('Array.prototype.findLast',
    function () { return typeof Array.prototype.findLast === 'function'; },
    function () {
      return define(Array.prototype, 'findLast', function findLast(predicate, thisArg) {
        for (var i = this.length - 1; i >= 0; i--) {
          if (i in this && predicate.call(thisArg, this[i], i, this)) { return this[i]; }
        }
        return undefined;
      });
    });

  ensure('Array.prototype.findLastIndex',
    function () { return typeof Array.prototype.findLastIndex === 'function'; },
    function () {
      return define(Array.prototype, 'findLastIndex', function findLastIndex(predicate, thisArg) {
        for (var i = this.length - 1; i >= 0; i--) {
          if (i in this && predicate.call(thisArg, this[i], i, this)) { return i; }
        }
        return -1;
      });
    });

  // --- Non-mutating array copies: Chromium 110 ------------------------------
  ensure('Array.prototype.toReversed',
    function () { return typeof Array.prototype.toReversed === 'function'; },
    function () {
      return define(Array.prototype, 'toReversed', function toReversed() {
        return slice(this).reverse();
      });
    });

  ensure('Array.prototype.toSorted',
    function () { return typeof Array.prototype.toSorted === 'function'; },
    function () {
      return define(Array.prototype, 'toSorted', function toSorted(compare) {
        return slice(this).sort(compare);
      });
    });

  ensure('Array.prototype.with',
    function () { return typeof Array.prototype.with === 'function'; },
    function () {
      return define(Array.prototype, 'with', function arrayWith(index, value) {
        var out = slice(this);
        var i = Number(index);
        if (i !== i) { i = 0; }           // NaN -> 0, per ToIntegerOrInfinity
        i = i < 0 ? Math.ceil(i) : Math.floor(i);
        if (i < 0) { i += out.length; }
        if (i < 0 || i >= out.length) { throw new RangeError('Invalid index: ' + index); }
        out[i] = value;
        return out;
      });
    });

  // --- String.prototype.toWellFormed / isWellFormed: Chromium 111 -----------
  ensure('String.prototype.toWellFormed',
    function () { return typeof String.prototype.toWellFormed === 'function'; },
    function () {
      var fix = function (input) {
        var text = String(input);
        var out = '';
        for (var i = 0; i < text.length; i++) {
          var code = text.charCodeAt(i);
          if (code >= 0xD800 && code <= 0xDBFF) {
            var next = text.charCodeAt(i + 1);
            if (next >= 0xDC00 && next <= 0xDFFF) {
              out += text.charAt(i) + text.charAt(i + 1);
              i++;
            } else {
              out += '\uFFFD';
            }
          } else if (code >= 0xDC00 && code <= 0xDFFF) {
            out += '\uFFFD';
          } else {
            out += text.charAt(i);
          }
        }
        return out;
      };
      var wellFormed = function (input) {
        var text = String(input);
        for (var i = 0; i < text.length; i++) {
          var code = text.charCodeAt(i);
          if (code >= 0xD800 && code <= 0xDBFF) {
            var next = text.charCodeAt(i + 1);
            if (!(next >= 0xDC00 && next <= 0xDFFF)) { return false; }
            i++;
          } else if (code >= 0xDC00 && code <= 0xDFFF) {
            return false;
          }
        }
        return true;
      };
      var ok = define(String.prototype, 'toWellFormed', function toWellFormed() {
        return fix(this);
      });
      define(String.prototype, 'isWellFormed', function isWellFormed() {
        return wellFormed(this);
      });
      return ok;
    });

  // --- Object.groupBy / Map.groupBy: Chromium 117 ---------------------------
  ensure('Object.groupBy',
    function () { return typeof Object.groupBy === 'function'; },
    function () {
      // The spec hands back a null-prototype object so a key of "__proto__"
      // cannot reach Object.prototype.
      return define(Object, 'groupBy', function groupBy(items, callback) {
        var out = Object.create(null);
        var index = 0;
        var iterator = items[Symbol.iterator]();
        var step;
        while (!(step = iterator.next()).done) {
          var value = step.value;
          var key = callback(value, index++);
          if (key in out) { out[key].push(value); } else { out[key] = [value]; }
        }
        return out;
      });
    });

  ensure('Map.groupBy',
    function () { return typeof Map.groupBy === 'function'; },
    function () {
      return define(Map, 'groupBy', function groupBy(items, callback) {
        var out = new Map();
        var index = 0;
        var iterator = items[Symbol.iterator]();
        var step;
        while (!(step = iterator.next()).done) {
          var value = step.value;
          var key = callback(value, index++);
          var bucket = out.get(key);
          if (bucket === undefined) { out.set(key, [value]); } else { bucket.push(value); }
        }
        return out;
      });
    });

  // --- Set methods: Chromium 122 --------------------------------------------
  function asSet(value) { return value instanceof Set ? value : new Set(value); }

  ensure('Set.prototype.union',
    function () { return typeof Set.prototype.union === 'function'; },
    function () {
      define(Set.prototype, 'union', function union(other) {
        var out = new Set(this);
        asSet(other).forEach(function (value) { out.add(value); });
        return out;
      });
      define(Set.prototype, 'intersection', function intersection(other) {
        var out = new Set();
        var right = asSet(other);
        this.forEach(function (value) { if (right.has(value)) { out.add(value); } });
        return out;
      });
      define(Set.prototype, 'difference', function difference(other) {
        var out = new Set();
        var right = asSet(other);
        this.forEach(function (value) { if (!right.has(value)) { out.add(value); } });
        return out;
      });
      define(Set.prototype, 'symmetricDifference', function symmetricDifference(other) {
        var self = this;
        var right = asSet(other);
        var out = new Set();
        self.forEach(function (value) { if (!right.has(value)) { out.add(value); } });
        right.forEach(function (value) { if (!self.has(value)) { out.add(value); } });
        return out;
      });
      define(Set.prototype, 'isSubsetOf', function isSubsetOf(other) {
        var self = this;
        var right = asSet(other);
        var ok = true;
        self.forEach(function (value) { if (!right.has(value)) { ok = false; } });
        return ok;
      });
      define(Set.prototype, 'isSupersetOf', function isSupersetOf(other) {
        var self = this;
        var ok = true;
        asSet(other).forEach(function (value) { if (!self.has(value)) { ok = false; } });
        return ok;
      });
      define(Set.prototype, 'isDisjointFrom', function isDisjointFrom(other) {
        var self = this;
        var right = asSet(other);
        var ok = true;
        self.forEach(function (value) { if (right.has(value)) { ok = false; } });
        return ok;
      });
      return true;
    });

  // --- URL.parse / URL.canParse: Chromium 126 / 120 -------------------------
  ensure('URL.parse',
    function () { return typeof URL.parse === 'function'; },
    function () {
      define(URL, 'canParse', function canParse(input, base) {
        try {
          if (base === undefined) { new URL(input); } else { new URL(input, base); }
          return true;
        } catch (e) { return false; }
      });
      return define(URL, 'parse', function parse(input, base) {
        try {
          return base === undefined ? new URL(input) : new URL(input, base);
        } catch (e) { return null; }
      });
    });

  // --- ArrayBuffer transfer: Chromium 114 -----------------------------------
  // pdf.js calls this while compiling an embedded font's info, which happens
  // for essentially every PDF that embeds a font. Without it the preview
  // throws instead of rendering.
  ensure('ArrayBuffer.prototype.transferToFixedLength',
    function () { return typeof ArrayBuffer.prototype.transferToFixedLength === 'function'; },
    function () {
      // structuredClone is the only portable way to detach an ArrayBuffer, and
      // it needs Chromium 98. Below that the copy is still right, the source
      // simply stays readable instead of throwing on next use.
      var detach = function (buffer) {
        if (typeof structuredClone !== 'function') { return; }
        try { structuredClone(buffer, { transfer: [buffer] }); } catch (e) { /* ignore */ }
      };
      var move = function (buffer, newLength) {
        var length = newLength === undefined ? buffer.byteLength : Number(newLength);
        if (length < 0 || length !== Math.floor(length)) {
          throw new RangeError('Invalid array buffer length');
        }
        var kept = Math.min(length, buffer.byteLength);
        var copy = buffer.slice(0, kept);
        detach(buffer);
        if (copy.byteLength === length) { return copy; }
        var padded = new ArrayBuffer(length);
        new Uint8Array(padded).set(new Uint8Array(copy));
        return padded;
      };
      // transfer() may hand back a resizable buffer natively; ours is always
      // fixed-length, which is what every call site in the bundle wants.
      define(ArrayBuffer.prototype, 'transfer', function transfer(newLength) {
        return move(this, newLength);
      });
      return define(ArrayBuffer.prototype, 'transferToFixedLength',
        function transferToFixedLength(newLength) {
          return move(this, newLength);
        });
    });

  // --- Well-known symbols: Chromium 134 -------------------------------------
  ensure('Symbol.dispose',
    function () { return typeof Symbol.dispose === 'symbol'; },
    function () {
      define(Symbol, 'dispose', Symbol('Symbol.dispose'));
      define(Symbol, 'asyncDispose', Symbol('Symbol.asyncDispose'));
      return true;
    });

  // --- Insecure-origin gaps -------------------------------------------------
  // These are not about the engine's age: both APIs are [SecureContext], and
  // this app talks to a LAN address over plain HTTP.

  try {
    if (typeof crypto !== 'undefined' && !crypto.randomUUID) {
      var uuid = define(crypto, 'randomUUID', function randomUUID() {
        var bytes = new Uint8Array(16);
        crypto.getRandomValues(bytes);
        bytes[6] = (bytes[6] & 0x0f) | 0x40;
        bytes[8] = (bytes[8] & 0x3f) | 0x80;
        var hex = [];
        for (var i = 0; i < 16; i++) { hex.push((bytes[i] + 0x100).toString(16).slice(1)); }
        return hex.slice(0, 4).join('') + '-' + hex.slice(4, 6).join('') + '-' +
          hex.slice(6, 8).join('') + '-' + hex.slice(8, 10).join('') + '-' +
          hex.slice(10, 16).join('');
      });
      if (uuid) { applied.push('crypto.randomUUID'); } else { gaps.push('crypto.randomUUID'); }
    }
  } catch (e) { gaps.push('crypto.randomUUID'); }

  // Every copy button in the UI is dead over plain HTTP. execCommand still
  // works there, and it works synchronously inside the click that asked for it.
  try {
    if (typeof navigator !== 'undefined' && typeof document !== 'undefined' &&
        !navigator.clipboard) {
      var writeText = function (text) {
        return new Promise(function (resolve, reject) {
          var area = document.createElement('textarea');
          area.value = String(text);
          area.setAttribute('readonly', '');
          area.style.position = 'fixed';
          area.style.top = '-1000px';
          area.style.opacity = '0';
          document.body.appendChild(area);
          var copied = false;
          try {
            area.select();
            copied = document.execCommand('copy');
          } catch (e) { copied = false; }
          document.body.removeChild(area);
          if (copied) { resolve(); }
          else { reject(new Error('clipboard is not available on an insecure origin')); }
        });
      };
      var installed = define(navigator, 'clipboard', {
        writeText: writeText,
        readText: function () {
          return Promise.reject(new Error('clipboard read needs a secure origin'));
        }
      });
      if (installed) { applied.push('navigator.clipboard.writeText'); }
      else { gaps.push('navigator.clipboard'); }
    }
  } catch (e) { gaps.push('navigator.clipboard'); }

  // structuredClone is intentionally NOT shimmed: a clone that is subtly wrong
  // corrupts state silently, which is worse to debug than a missing method.
  try {
    if (typeof structuredClone !== 'function') { gaps.push('structuredClone (not shimmed)'); }
  } catch (e) { /* ignore */ }

  // DiagnosticsScript prefixes every line with "compat: ", so these read as
  // "compat: SHIMMED ..." in the log the user copies out of the app.
  if (applied.length) {
    report('SHIMMED ' + applied.join(', ') + ' (engine too old or origin insecure)');
  }
  if (gaps.length) { report('MISSING (no shim available): ' + gaps.join(', ')); }
  if (!applied.length && !gaps.length) { report('nothing needed'); }
})();
''';
}
