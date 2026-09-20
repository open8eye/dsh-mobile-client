import 'package:dsh_mobile_client/core/browser/overscroll_script.dart';
import 'package:flutter_test/flutter_test.dart';

/// The overscroll guard is injected as a string, so nothing type-checks it.
/// These tests pin down the parts that would silently stop working if the
/// string drifted: the CSS property that actually suppresses the gesture, the
/// id that keeps a second injection a no-op, and the two blunt instruments it
/// must not reach for.
void main() {
  group('OverscrollScript', () {
    test('suppresses the horizontal overscroll the swipe-back rides on', () {
      expect(OverscrollScript.source, contains('overscroll-behavior-x:none'));
    });

    test('keeps vertical overscroll inside the scroller', () {
      // 'none' on this axis would also kill the bounce the DSH shell relies on,
      // so the vertical rule is deliberately weaker than the horizontal one.
      expect(OverscrollScript.source, contains('overscroll-behavior-y:contain'));
      expect(OverscrollScript.source, isNot(contains('overscroll-behavior-y:none')));
    });

    test('does not disable scrolling itself', () {
      // touch-action and overflow are the blunt instruments here: either would
      // break the DSH shell's own horizontal scrollers.
      expect(OverscrollScript.source, isNot(contains('touch-action')));
      expect(OverscrollScript.source, isNot(contains('overflow')));
    });

    test('injects the style under the advertised id, exactly once', () {
      expect(OverscrollScript.source, contains(OverscrollScript.styleId));
      expect(OverscrollScript.source, contains('getElementById'));
    });

    test('waits for a <head> instead of assuming one exists', () {
      // At document start there is no <head>, and appending to a null one would
      // throw before the guard ever ran.
      expect(OverscrollScript.source, contains('MutationObserver'));
      expect(OverscrollScript.source, contains('document.head'));
    });
  });
}
