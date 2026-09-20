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
}
