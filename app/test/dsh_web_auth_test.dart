import 'package:dsh_mobile_client/core/diagnostics/diagnostics_script.dart';
import 'package:flutter_test/flutter_test.dart';

/// `isDshWebAuthRejection` decides whether the app throws away the session
/// cookie and retries, and it reads a string that lives on the *server* side.
/// These tests pin that string and the shape of the probe it is read out of —
/// if either drifts, the recovery silently stops happening and the user is back
/// to being told their access password expired when it did not.
void main() {
  /// A probe result as [DiagnosticsScript.probeSource] produces it: whitespace
  /// collapsed, first 160 characters kept.
  Map<String, Object?> probeOf(String body) => <String, Object?>{
        'state': 'ok',
        'textLength': body.length,
        'textHead': body.replaceAll(RegExp(r'\s+'), ' ').trim(),
      };

  group('DiagnosticsScript.isDshWebAuthRejection', () {
    test('recognises the exact line dsh web answers a dead session with', () {
      expect(
        DiagnosticsScript.isDshWebAuthRejection(probeOf(
          'dsh web authentication required; reopen the URL printed by dsh web.\n',
        )),
        isTrue,
      );
    });

    test('the marker survives the probe collapsing whitespace', () {
      // The real body is a single line, but a proxy is free to reformat it.
      expect(
        DiagnosticsScript.isDshWebAuthRejection(probeOf(
          '  dsh web authentication required;\n  reopen the URL printed by dsh web.  ',
        )),
        isTrue,
      );
    });

    test('the proxy login page is not it — that one is the PIN, and is asked for', () {
      expect(
        DiagnosticsScript.isDshWebAuthRejection(probeOf(
          '🔐 DSH Pocket 此局域网地址受访问密码保护，请输入 8 位密码 | Enter the 8-character PIN',
        )),
        isFalse,
      );
    });

    test('a rendered DSH page is not it', () {
      expect(
        DiagnosticsScript.isDshWebAuthRejection(probeOf('DeepSeek Harness 新会话 发送')),
        isFalse,
      );
    });

    test('no probe, a failed probe, or a non-string head is not it', () {
      expect(DiagnosticsScript.isDshWebAuthRejection(null), isFalse);
      expect(
        DiagnosticsScript.isDshWebAuthRejection(<String, Object?>{'state': 'no-body'}),
        isFalse,
      );
      expect(
        DiagnosticsScript.isDshWebAuthRejection(
          <String, Object?>{'state': 'ok', 'textHead': 42},
        ),
        isFalse,
      );
    });

    test('the 401 body is not "blank", so the HTTP failure still stands', () {
      // Guards the two helpers staying in step: if this body ever counted as
      // blank, the app would report a white screen instead of the 401 the
      // recovery branch is keyed on.
      final probe = probeOf(
        'dsh web authentication required; reopen the URL printed by dsh web.',
      );
      expect(DiagnosticsScript.looksBlank(probe), isFalse);
    });
  });
}
