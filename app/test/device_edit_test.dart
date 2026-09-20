import 'package:dsh_mobile_client/core/i18n/l10n.dart';
import 'package:dsh_mobile_client/core/models/dsh_device.dart';
import 'package:dsh_mobile_client/features/devices/device_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The add/edit form is the one screen a user reaches while holding the access
/// password in their head, so it is also the screen most likely to make them
/// type it twice. These tests pin down that it does not ask at all.
void main() {
  const stored = DshDevice(
    id: 'a',
    name: '书房台式机',
    baseUrl: 'http://192.168.1.5:3081',
    kind: DshAccessKind.lan,
    hasPassword: true,
  );
  const bare = DshDevice(
    id: 'b',
    name: '书房台式机',
    baseUrl: 'http://192.168.1.5:3081',
    kind: DshAccessKind.lan,
  );

  group('DeviceEditScreen', () {
    testWidgets('never asks for the access password', (tester) async {
      // The password is captured by the native prompt at the moment the server
      // actually asks for it — the only moment a wrong PIN can be told from a
      // right one. A field here made the user type the same PIN twice: once
      // into this form, and again when the session opened.
      await _open(tester, device: stored);
      expect(find.text('访问密码'), findsNothing);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('服务器地址'), findsOneWidget);
      expect(find.text('设备昵称'), findsOneWidget);
    });

    testWidgets('reports what is stored without showing it', (tester) async {
      // The secret is not even handed to this screen, so it cannot end up in a
      // screenshot of the settings page.
      await _open(tester, device: stored);
      expect(find.text('访问密码已保存'), findsOneWidget);
      expect(find.text('清除'), findsOneWidget);
    });

    testWidgets('a device with no password says what will happen', (tester) async {
      await _open(tester, device: bare);
      expect(find.text('访问密码已保存'), findsNothing);
      expect(find.text('清除'), findsNothing);
      expect(find.textContaining('连接时会提示输入访问密码'), findsOneWidget);
    });

    testWidgets('saving an untouched form asks for nothing to be cleared', (tester) async {
      final result = await _open(tester, device: stored, save: true);
      expect(result, isNotNull);
      expect(result!.clearPassword, isFalse);
      expect(result.name, '书房台式机');
      expect(result.endpoint.baseUrl, 'http://192.168.1.5:3081');
    });

    testWidgets('clearing is only reported once the user asks for it', (tester) async {
      final result = await _open(tester, device: stored, clear: true, save: true);
      expect(result!.clearPassword, isTrue);
    });

    testWidgets('clearing can be taken back before saving', (tester) async {
      final result = await _open(tester, device: stored, clear: true, undo: true, save: true);
      expect(result!.clearPassword, isFalse);
    });

    testWidgets('an empty address is refused instead of saved', (tester) async {
      final result = await _open(tester, device: null, address: '', save: true);
      expect(result, isNull, reason: 'the form should have stayed open');
      expect(find.text('请填写服务器地址'), findsOneWidget);
    });

    testWidgets('an address that is not a URL is refused', (tester) async {
      final result = await _open(tester, device: null, address: 'not a host', save: true);
      expect(result, isNull);
      expect(find.textContaining('地址无效'), findsOneWidget);
    });
  });
}

/// Open the screen on a real route so its pop result can be inspected.
Future<DeviceFormResult?> _open(
  WidgetTester tester, {
  required DshDevice? device,
  String? address,
  bool clear = false,
  bool undo = false,
  bool save = false,
}) async {
  DeviceFormResult? captured;
  await tester.pumpWidget(
    L10nScope(
      l10n: const L10n('zh'),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await Navigator.of(context).push<DeviceFormResult>(
                    MaterialPageRoute<DeviceFormResult>(
                      builder: (_) => DeviceEditScreen(device: device),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  if (address != null) {
    await tester.enterText(find.byType(TextFormField).first, address);
    await tester.pump();
  }
  if (clear) {
    await tester.tap(find.text('清除'));
    await tester.pump();
  }
  if (undo) {
    await tester.tap(find.text('不清除'));
    await tester.pump();
  }
  if (save) {
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
  }
  return captured;
}
