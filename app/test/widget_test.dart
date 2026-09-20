import 'package:dsh_mobile_client/core/dsh/dsh_endpoint.dart';
import 'package:dsh_mobile_client/core/models/dsh_device.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DshEndpoint.tryParse', () {
    test('accepts the bare URL a dsh-pocket LAN QR code carries', () {
      final endpoint = DshEndpoint.tryParse('http://192.168.1.5:3081');
      expect(endpoint, isNotNull);
      expect(endpoint!.baseUrl, 'http://192.168.1.5:3081');
      expect(endpoint.password, isNull);
      expect(endpoint.kind, DshAccessKind.lan);
    });

    test('pulls the password out of a share link and drops it from the base URL', () {
      final endpoint = DshEndpoint.tryParse('http://192.168.1.5:3081/?token=Ab3xY9Zq');
      expect(endpoint, isNotNull);
      expect(endpoint!.baseUrl, 'http://192.168.1.5:3081');
      expect(endpoint.password, 'Ab3xY9Zq');
    });

    test('adds a scheme when the user types a bare host', () {
      final endpoint = DshEndpoint.tryParse('192.168.1.5:3081');
      expect(endpoint?.baseUrl, 'http://192.168.1.5:3081');
    });

    test('classifies Tailscale CGNAT as its own kind, matching the server', () {
      final endpoint = DshEndpoint.tryParse('http://100.111.56.77:3081');
      expect(endpoint?.kind, DshAccessKind.tailscale);
    });

    test('classifies a quick tunnel as public', () {
      final endpoint = DshEndpoint.tryParse('https://calm-river-1234.trycloudflare.com');
      expect(endpoint?.kind, DshAccessKind.tunnel);
    });

    test('keeps a reverse-proxy sub-path', () {
      final endpoint = DshEndpoint.tryParse('https://example.com/dsh/?token=xyz');
      expect(endpoint?.baseUrl, 'https://example.com/dsh');
      expect(endpoint?.password, 'xyz');
    });

    test('rejects things that are not addresses', () {
      expect(DshEndpoint.tryParse(''), isNull);
      expect(DshEndpoint.tryParse('   '), isNull);
      expect(DshEndpoint.tryParse('ftp://example.com'), isNull);
      // Uri.parse is lenient enough to read this as host "not"; reject it.
      expect(DshEndpoint.tryParse('not a url at all'), isNull);
    });

    test('keeps an IPv6 host bracketed', () {
      final endpoint = DshEndpoint.tryParse('http://[::1]:3081/?token=abc');
      expect(endpoint?.baseUrl, 'http://[::1]:3081');
      expect(endpoint?.password, 'abc');
    });

    test('builds a one-hop authenticated URL on the root path', () {
      final endpoint = DshEndpoint.tryParse('http://192.168.1.5:3081')!;
      expect(
        endpoint.authenticatedUrl('Ab3xY9Zq'),
        'http://192.168.1.5:3081/?token=Ab3xY9Zq',
      );
    });
  });

  group('DshDevice', () {
    test('round-trips through JSON', () {
      final device = DshDevice(
        id: 'abc',
        name: '书房台式机',
        baseUrl: 'http://192.168.1.5:3081',
        kind: DshAccessKind.lan,
        hasPassword: true,
        createdAt: DateTime.parse('2024-01-01T00:00:00.000'),
      );
      final restored = DshDevice.fromJson(device.toJson());
      expect(restored?.id, device.id);
      expect(restored?.name, device.name);
      expect(restored?.baseUrl, device.baseUrl);
      expect(restored?.kind, DshAccessKind.lan);
      expect(restored?.hasPassword, isTrue);
    });

    test('rejects a malformed record instead of throwing', () {
      expect(DshDevice.fromJson(<String, Object?>{'id': 1}), isNull);
    });

    test('round-trips the alternate address', () {
      const device = DshDevice(
        id: 'abc',
        name: '书房台式机',
        baseUrl: 'http://192.168.1.5:3081',
        kind: DshAccessKind.lan,
        altBaseUrls: <String>['http://100.111.56.77:3081'],
      );
      expect(DshDevice.fromJson(device.toJson())?.altBaseUrls,
          <String>['http://100.111.56.77:3081']);
      expect(device.candidates, <String>[
        'http://192.168.1.5:3081',
        'http://100.111.56.77:3081',
      ]);
    });

    test('a record written before alternate addresses existed still loads', () {
      // The whole point of the field being optional: an upgrade must not
      // lose the devices the user already had.
      final restored = DshDevice.fromJson(<String, Object?>{
        'id': 'abc',
        'name': '书房台式机',
        'baseUrl': 'http://192.168.1.5:3081',
        'kind': 'lan',
        'hasPassword': true,
      });
      expect(restored, isNotNull);
      expect(restored!.altBaseUrls, isEmpty);
      expect(restored.candidates, <String>['http://192.168.1.5:3081']);
    });

    test('junk in the alternate list is dropped, not trusted', () {
      final restored = DshDevice.fromJson(<String, Object?>{
        'id': 'abc',
        'name': 'a',
        'baseUrl': 'http://192.168.1.5:3081',
        'kind': 'lan',
        'altBaseUrls': <Object?>[1, '', 'http://ok:3081', null],
      });
      expect(restored!.altBaseUrls, <String>['http://ok:3081']);
    });

    test('reports the effective port for the default scheme', () {
      const device = DshDevice(
        id: 'a',
        name: 'a',
        baseUrl: 'https://example.com',
        kind: DshAccessKind.tunnel,
      );
      expect(device.port, 443);
      expect(device.address, 'example.com:443');
    });
  });
}
