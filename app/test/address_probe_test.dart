import 'dart:async';

import 'package:dsh_mobile_client/core/dsh/address_probe.dart';
import 'package:flutter_test/flutter_test.dart';

/// The probe decides which address a session loads. Getting it wrong means
/// either waiting on an address that cannot work, or loading one that does not
/// — so the interesting cases are the ones where the list order and the right
/// answer disagree.
void main() {
  group('AddressProbe', () {
    test('a lone address is used as-is, without a round trip', () async {
      var probed = 0;
      final probe = AddressProbe(probe: (_) async {
        probed++;
        return false;
      });
      expect(await probe.firstReachable(<String>['http://only']), 'http://only');
      expect(probed, 0, reason: 'probing one candidate only adds latency');
    });

    test('no addresses means nothing to try', () async {
      final probe = AddressProbe(probe: (_) async => true);
      expect(await probe.firstReachable(<String>[]), isNull);
    });

    test('the fastest answer wins, not the first in the list', () async {
      final late = Completer<bool>();
      final probe = AddressProbe(
        probe: (uri) async => uri.host == 'slow' ? late.future : true,
      );
      expect(
        await probe.firstReachable(<String>['http://slow', 'http://fast']),
        'http://fast',
      );
      late.complete(true);
    });

    test('an address that never answers is passed over', () async {
      final dead = Completer<bool>();
      final probe = AddressProbe(
        probe: (uri) async => uri.host == 'dead' ? dead.future : true,
      );
      expect(
        await probe.firstReachable(<String>['http://dead', 'http://live']),
        'http://live',
      );
      dead.complete(false);
    });

    test('the first answer is returned without waiting for the rest', () async {
      final late = Completer<bool>();
      final probe = AddressProbe(
        probe: (uri) async => uri.host == 'quick' ? true : late.future,
      );
      expect(
        await probe.firstReachable(<String>['http://slow', 'http://quick']),
        'http://quick',
      );
      late.complete(true);
    });

    test('when nothing answers the caller gets null, not a guess', () async {
      final probe = AddressProbe(probe: (_) async => false);
      expect(await probe.firstReachable(<String>['http://a', 'http://b']), isNull);
    });

    test('a malformed entry does not hold up the others', () async {
      final probe = AddressProbe(probe: (uri) async => uri.host == 'good');
      expect(
        await probe.firstReachable(<String>['not a url', 'http://good']),
        'http://good',
      );
    });

    test('a failure that arrives first does not win', () async {
      final probe = AddressProbe(probe: (uri) async => uri.host != 'bad');
      expect(
        await probe.firstReachable(<String>['http://bad', 'http://good']),
        'http://good',
      );
    });
  });
}
