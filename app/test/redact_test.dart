import 'package:dsh_mobile_client/core/diagnostics/diagnostics_script.dart';
import 'package:dsh_mobile_client/core/diagnostics/log_entry.dart';
import 'package:dsh_mobile_client/core/diagnostics/redact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Redact by parameter name', () {
    test('scrubs the token this app actually builds', () {
      // The exact shape DshEndpoint.authenticatedUrl produces. If this leaks,
      // every bug report hands out access to the user's machine.
      expect(
        Redact.url('http://192.168.1.5:3081/?token=123456'),
        'http://192.168.1.5:3081/?token=${Redact.placeholder}',
      );
    });

    test('scrubs token in any position and leaves the rest of the query', () {
      expect(
        Redact.url('https://x.dev/p?token=abc&view=chat&tab=1'),
        'https://x.dev/p?token=${Redact.placeholder}&view=chat&tab=1',
      );
      expect(
        Redact.url('https://x.dev/p?a=1&token=abc'),
        'https://x.dev/p?a=1&token=${Redact.placeholder}',
      );
    });

    test('keeps the fragment after a token', () {
      expect(
        Redact.url('http://h:3081/?token=abc#/session/9'),
        'http://h:3081/?token=${Redact.placeholder}#/session/9',
      );
    });

    test('is case insensitive', () {
      expect(Redact.url('http://h/?TOKEN=abc'), 'http://h/?TOKEN=${Redact.placeholder}');
      expect(Redact.url('http://h/?Token=abc'), 'http://h/?Token=${Redact.placeholder}');
    });

    test('covers the other credential parameter names', () {
      for (final name in <String>['pin', 'password', 'passwd', 'pwd', 'secret', 'key', 'access_token']) {
        expect(
          Redact.url('http://h/?$name=hunter2'),
          'http://h/?$name=${Redact.placeholder}',
          reason: 'parameter $name must be scrubbed',
        );
      }
    });

    test('does not maul lookalike parameters', () {
      // 'keyword' starts with 'key' but is not a credential.
      const input = 'http://h/?keyword=cats&token=abc';
      expect(Redact.url(input), 'http://h/?keyword=cats&token=${Redact.placeholder}');
    });

    test('scrubs every occurrence, not just the first', () {
      final out = Redact.url('http://h/?token=a then http://h/?token=b');
      expect(out, isNot(contains('token=a')));
      expect(out, isNot(contains('token=b')));
      expect(out.split(Redact.placeholder).length - 1, 2);
    });
  });

  group('Redact by known secret', () {
    test('erases the literal PIN wherever it appears', () {
      const pin = '482913';
      final out = Redact.text(
        'loaded $pin for device; PIN entry $pin accepted; title="$pin"',
        secrets: <String>[pin],
      );
      expect(out, isNot(contains(pin)));
      expect(out, contains(Redact.placeholder));
    });

    test('catches the PIN outside a URL, where name matching cannot help', () {
      const pin = 'my-secret-pin';
      expect(
        Redact.text('session cookie bound to $pin', secrets: <String>[pin]),
        'session cookie bound to ${Redact.placeholder}',
      );
    });

    test('ignores secrets too short to redact safely', () {
      // Replacing a 1-2 char secret would shred the whole log.
      expect(Redact.text('abc', secrets: <String>['a']), 'abc');
      expect(Redact.text('port 80 open', secrets: <String>['80']), 'port 80 open');
    });

    test('still catches a short secret when it travels as a parameter', () {
      expect(
        Redact.text('http://h/?token=12', secrets: <String>['12']),
        'http://h/?token=${Redact.placeholder}',
      );
    });

    test('survives several secrets at once', () {
      final out = Redact.text(
        'a=aaaa b=bbbb',
        secrets: <String>['aaaa', 'bbbb'],
      );
      expect(out, 'a=${Redact.placeholder} b=${Redact.placeholder}');
    });
  });

  group('Redact headers', () {
    test('scrubs authorization and cookie values', () {
      expect(
        Redact.text('Authorization: Bearer abc.def.ghi'),
        'Authorization: ${Redact.placeholder}',
      );
      expect(
        Redact.text('Cookie: dsh-pocket=9f8e7d'),
        'Cookie: ${Redact.placeholder}',
      );
      expect(
        Redact.text('Set-Cookie: a=1; HttpOnly'),
        'Set-Cookie: ${Redact.placeholder}',
      );
    });
  });

  group('Redact leaves ordinary text alone', () {
    test('a plain URL is untouched', () {
      const url = 'http://192.168.1.5:3081/session/abc?view=chat';
      expect(Redact.url(url), url);
    });

    test('an empty secret list is safe', () {
      expect(Redact.text('nothing to hide'), 'nothing to hide');
      expect(Redact.text(''), '');
    });
  });

  group('LogEntry', () {
    test('formats as a fixed-width line', () {
      final entry = LogEntry(
        time: DateTime(2025, 1, 2, 3, 4, 5, 67),
        level: LogLevel.warn,
        tag: 'WebView',
        message: 'hello',
      );
      expect(entry.format(), '03:04:05.067 W/WebView  hello');
    });

    test('every level has a distinct letter', () {
      final letters = LogLevel.values.map((level) => level.letter).toSet();
      expect(letters.length, LogLevel.values.length);
    });
  });

  group('DiagnosticsScript', () {
    test('flags a document that loaded but never painted', () {
      expect(
        DiagnosticsScript.looksBlank(<String, Object?>{
          'state': 'ok',
          'textLength': 0,
          'bodyChildren': 1,
        }),
        isTrue,
      );
    });

    test('does not flag a page that rendered', () {
      expect(
        DiagnosticsScript.looksBlank(<String, Object?>{
          'state': 'ok',
          'textLength': 812,
          'bodyChildren': 3,
        }),
        isFalse,
      );
    });

    test('a failed probe is not a blank page', () {
      expect(
        DiagnosticsScript.looksBlank(<String, Object?>{'state': 'probe-failed'}),
        isFalse,
      );
    });

    test('describes a probe for the log', () {
      expect(
        DiagnosticsScript.describeProbe(<String, Object?>{
          'state': 'ok',
          'textLength': 0,
          'bodyChildren': 1,
          'mountFound': true,
          'mountChildren': 0,
          'scripts': 4,
          'readyState': 'complete',
        }),
        'page probe: text=0 bodyChildren=1 mount=true/0 scripts=4 ready=complete',
      );
    });
  });
}
