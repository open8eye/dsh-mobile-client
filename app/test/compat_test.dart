import 'dart:io';

import 'package:dsh_mobile_client/core/browser/compat_script.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CompatScript.chromiumMajor', () {
    test('reads the major version of a real WebView build', () {
      expect(CompatScript.chromiumMajor('83.0.4103.101'), 83);
      expect(CompatScript.chromiumMajor('130.0.6723.86'), 130);
      expect(CompatScript.chromiumMajor('83'), 83);
      expect(CompatScript.chromiumMajor('  83.0.4103.101  '), 83);
    });

    test('returns null rather than guessing', () {
      expect(CompatScript.chromiumMajor(null), isNull);
      expect(CompatScript.chromiumMajor(''), isNull);
      expect(CompatScript.chromiumMajor('unknown'), isNull);
      expect(CompatScript.chromiumMajor('v83'), isNull);
    });
  });

  group('CompatScript.isTooOld', () {
    test('flags the WebView that actually failed in the field', () {
      // Redmi K20 Pro / MIUI 12, taken from a real diagnostic report. Chromium
      // 83 predates the ??= operator the bundle uses, so the file never parses
      // and the page stays white no matter what shims are installed.
      expect(CompatScript.isTooOld('83.0.4103.101'), isTrue);
    });

    test('the declared floor is accepted, one below is not', () {
      // 94 is the static-block floor, not the ??= floor: fixing the operators
      // would only move the parse error further down the same file.
      expect(CompatScript.minimumChromium, 94);
      expect(CompatScript.isTooOld('94.0.4606.85'), isFalse);
      expect(CompatScript.isTooOld('93.0.4577.82'), isTrue);
    });

    test('a WebView that only clears the ??= floor is still rejected', () {
      // Chromium 90 parses ??= but not static {}, so it would white-screen too.
      expect(CompatScript.isTooOld('90.0.4430.91'), isTrue);
      expect(CompatScript.isTooOld('85.0.4183.101'), isTrue);
    });

    test('a current WebView is not flagged', () {
      expect(CompatScript.isTooOld('130.0.6723.86'), isFalse);
    });

    test('an unreadable version is never treated as old', () {
      // Attempting the load is better than blocking a device we cannot read.
      expect(CompatScript.isTooOld(null), isFalse);
      expect(CompatScript.isTooOld('unknown'), isFalse);
      expect(CompatScript.isTooOld(''), isFalse);
    });
  });

  group('CompatScript.source', () {
    // The doc comment above the class is the contract; the script is the
    // implementation. Nothing in the build notices when one moves without the
    // other, and a shim that documents an API it no longer installs is worse
    // than no documentation at all.
    const labels = <String>[
      'Object.hasOwn',
      'Array.prototype.at',
      'String.prototype.at',
      'String.prototype.replaceAll',
      'Promise.withResolvers',
      'Promise.try',
      'AbortSignal.any',
      'AbortSignal.timeout',
      'Array.prototype.findLast',
      'Array.prototype.findLastIndex',
      'Array.prototype.toReversed',
      'Array.prototype.toSorted',
      'Array.prototype.with',
      'String.prototype.toWellFormed',
      'Object.groupBy',
      'Map.groupBy',
      'Set.prototype.union',
      'URL.parse',
      'ArrayBuffer.prototype.transferToFixedLength',
      'Symbol.dispose',
      'crypto.randomUUID',
      'navigator.clipboard.writeText',
    ];

    test('every shim reports itself under the name the docs use', () {
      for (final label in labels) {
        expect(
          CompatScript.source,
          contains("'$label'"),
          reason: '$label is documented but never installed or reported',
        );
      }
    });

    test('the findings are parked where DiagnosticsScript looks', () {
      // The shim runs at document-start, before the Flutter bridge exists, so
      // a direct bridge call would be dropped on the floor. DiagnosticsScript
      // drains this global once the bridge is up.
      expect(CompatScript.source, contains('window.__dshCompatReport'));
      expect(CompatScript.source, isNot(contains('dshDiag.log')));
      final diagnostics =
          File('lib/core/diagnostics/diagnostics_script.dart').readAsStringSync();
      expect(
        diagnostics,
        contains('__dshCompatReport'),
        reason: 'the two scripts stopped agreeing on the channel',
      );
    });

    test('every version shim goes through ensure()', () {
      // ensure() is the only place that checks for the native implementation,
      // so a shim that skips it can overwrite a perfectly good engine.
      expect("ensure('".allMatches(CompatScript.source).length, 20);
    });

    test('structuredClone is reported rather than faked', () {
      // A clone that is subtly wrong corrupts state silently; a missing method
      // throws where the bug is. Only one of those is debuggable from a phone.
      expect(CompatScript.source, contains('structuredClone'));
      expect(CompatScript.source, isNot(contains("'structuredClone'")));
    });
  });

  group('threshold parity with Android', () {
    test('the Kotlin kernel threshold matches the Dart one', () {
      // Dart decides whether to explain; Kotlin decides whether to swap in
      // another kernel. If the two ever disagree, one of them is lying to the
      // user, and nothing else in the build would notice.
      final file = File(
        'android/app/src/main/kotlin/com/dshmobile/dsh_mobile_client/WebViewKernel.kt',
      );
      expect(file.existsSync(), isTrue, reason: 'WebViewKernel.kt moved');
      final match = RegExp(r'const val MIN_CHROMIUM = (\d+)')
          .firstMatch(file.readAsStringSync());
      expect(match, isNotNull, reason: 'MIN_CHROMIUM not found in WebViewKernel.kt');
      expect(int.parse(match!.group(1)!), CompatScript.minimumChromium);
    });
  });
}
