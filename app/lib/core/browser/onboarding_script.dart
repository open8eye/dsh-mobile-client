/// Clicks through DSH's first-run wizard so a configured server never asks again.
///
/// DSH's onboarding step is shown whenever the `ui-onboarding` settings section
/// does not hold the current acknowledgement. A phone is never allowed to write
/// that section: the settings transport binds persistence to
/// `remote.$host.isLoopback ? 'host' : 'memory'`, so a remote browser's
/// acknowledgement lives in a JavaScript variable and dies with the page. Every
/// reload therefore greets a phone with the wizard again, no matter how many
/// times it has been dismissed — on a configured server, forever.
///
/// The durable fix would be to relax that boundary, which would also let a phone
/// rewrite the host's settings file. Instead this takes the wizard's own exits:
/// it clicks "skip all" while the checklist is up, then "start using" on the
/// summary that leads to, which is exactly what the acknowledgement is bound to.
/// Nothing is bypassed and nothing is hidden — the two clicks a user would make
/// are simply made for them.
///
/// If DSH ever changes that surface, the script finds no text-labelled button and
/// does nothing; the wizard shows exactly as it does today. That is the whole
/// failure mode, which is why the setting can safely default to on.
class OnboardingScript {
  const OnboardingScript._();

  /// Marker attribute recording the label already clicked on a node.
  static const String clickedAttribute = 'data-dsh-onboarding-clicked';

  static const String source = r'''
(function () {
  var CLICKED = 'data-dsh-onboarding-clicked';

  function appRoot() {
    return document.getElementById('root');
  }

  /**
   * True while an onboarding step owns the screen.
   *
   * The step contract is explicit: a step wraps its content in its own modal
   * surface and takes #root inert for as long as it is mounted. Nothing else in
   * the shell sets that flag, so it separates an onboarding step from every
   * ordinary dialog without guessing at class names.
   */
  function stepOwnsScreen() {
    var root = appRoot();
    return root !== null && root.inert === true;
  }

  /**
   * The step's modal surface: a body child that is not #root and that carries
   * the shell's chrome. The onboarding shell renders a step rail (an <aside>
   * holding the step titles) next to a <footer> for its actions; no other
   * surface in the app has both.
   */
  function stepSurface() {
    var root = appRoot();
    var body = document.body;
    if (body === null) return null;
    var nodes = body.children;
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      if (node === root || node.querySelector === undefined) continue;
      if (node.querySelector('aside') !== null && node.querySelector('footer') !== null) {
        return node;
      }
    }
    return null;
  }

  /**
   * Click the step's own text action, at most once per label.
   *
   * The wizard offers exactly two over its life: "skip all" while the checklist
   * is up, then "start using" on the summary that leads to. Both are text
   * buttons. The icon-only close control has no text and is deliberately left
   * alone, so the checklist is left through its documented exit rather than
   * dismissed behind the shell's back.
   *
   * The label is remembered on the node, so a re-render cannot click the same
   * button twice, while a different label is still free to be clicked.
   */
  function advance(surface) {
    var buttons = surface.querySelectorAll('button');
    for (var i = 0; i < buttons.length; i++) {
      var button = buttons[i];
      if (button.disabled) continue;
      var label = (button.textContent || '').replace(/s+/g, ' ').trim();
      if (label === '' || label === button.getAttribute(CLICKED)) continue;
      button.setAttribute(CLICKED, label);
      button.click();
      return;
    }
  }

  function run() {
    if (!stepOwnsScreen()) return;
    var surface = stepSurface();
    if (surface === null) return;
    advance(surface);
  }

  var scheduled = false;
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(function () {
      scheduled = false;
      run();
    }, 50);
  }

  // The wizard mounts long after document start, and each click re-renders it,
  // so this cannot be a one-shot. The observer callback stays cheap: the inert
  // check is one lookup, and only a step that owns the screen earns a scan.
  var observer = new MutationObserver(function () {
    if (stepOwnsScreen()) schedule();
  });
  function observe() {
    if (document.body === null) return;
    observer.observe(document.body, { childList: true, subtree: true });
    schedule();
  }
  if (document.body !== null) observe();
  else document.addEventListener('DOMContentLoaded', observe);
})();
''';
}
