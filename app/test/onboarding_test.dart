import 'package:dsh_mobile_client/core/browser/onboarding_script.dart';
import 'package:dsh_mobile_client/core/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// The onboarding guard runs inside someone else's DOM, so the tests pin down
/// the promises that make it safe to ship on by default: it acts only while an
/// onboarding step owns the screen, it only clicks that step's own text actions,
/// and when it does not recognise the surface it does nothing at all.
void main() {
  group('OnboardingScript', () {
    test('acts only while an onboarding step owns the screen', () {
      // #root inert is the step contract's own signal: the shell sets it while a
      // step is mounted and nothing else in the app sets it at all.
      expect(OnboardingScript.source, contains("getElementById('root')"));
      expect(OnboardingScript.source, contains('inert === true'));
    });

    test('never takes or releases #root inert itself', () {
      // Releasing it would leave the wizard mounted but harmless-looking, which
      // is worse than leaving it alone: the page behind is still mid-setup.
      expect(RegExp(r'\.inert\s*=(?!=)').hasMatch(OnboardingScript.source), isFalse);
    });

    test('never hides or removes anything', () {
      // Hiding is the tempting shortcut and the one that breaks: it would leave
      // the user staring at a page whose own setup flow thinks it is still up.
      expect(OnboardingScript.source, isNot(contains('.style')));
      expect(OnboardingScript.source, isNot(contains('removeChild')));
      expect(OnboardingScript.source, isNot(contains('.remove(')));
    });

    test('clicks text actions and leaves the icon-only close control alone', () {
      // The wizard's close button renders an icon and no text, so the empty
      // label filter is what keeps it out of reach.
      expect(OnboardingScript.source, contains('button.textContent'));
      expect(OnboardingScript.source, contains("label === ''"));
    });

    test('clicks any one label at most once', () {
      expect(OnboardingScript.source, contains(OnboardingScript.clickedAttribute));
      expect(OnboardingScript.source, contains('setAttribute(CLICKED, label)'));
    });

    test('skips disabled buttons', () {
      // "Start using" is disabled while the acknowledgement is being saved.
      expect(OnboardingScript.source, contains('button.disabled'));
    });

    test('expects the wizard to mount after document start', () {
      expect(OnboardingScript.source, contains('MutationObserver'));
      expect(OnboardingScript.source, contains('DOMContentLoaded'));
    });
  });

  group('AppSettings.skipDshOnboarding', () {
    test('is on by default', () {
      // Anyone arriving through this app already has a configured DSH, and a
      // phone can never persist the acknowledgement, so the wizard would come
      // back on every single reload.
      expect(const AppSettings().skipDshOnboarding, isTrue);
    });

    test('survives a JSON round trip', () {
      final off = const AppSettings().copyWith(skipDshOnboarding: false);
      expect(off.skipDshOnboarding, isFalse);
      expect(AppSettings.fromJson(off.toJson()).skipDshOnboarding, isFalse);
      expect(
        AppSettings.fromJson(const AppSettings().toJson()).skipDshOnboarding,
        isTrue,
      );
    });

    test('an older record without the key reads as on', () {
      final legacy = AppSettings.fromJson(<String, Object?>{'autoReconnect': true});
      expect(legacy.skipDshOnboarding, isTrue);
    });
  });
}
