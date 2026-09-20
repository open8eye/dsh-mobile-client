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
/// it clicks "skip all" while the checklist is up, then the single action on the
/// summary that leads to, which is exactly what the acknowledgement is bound to.
/// Nothing is bypassed and nothing is hidden — the clicks a user would make are
/// simply made for them.
///
/// Both actions are found by *structure*, never by copy, because the wizard's
/// buttons are not interchangeable: the surface also carries a language menu and
/// a row of per-task buttons, and clicking those would be worse than doing
/// nothing. See [source] for the two shapes it recognises.
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
   * Send a finding back to the app's diagnostics channel.
   *
   * The hook is installed by an earlier user script and owns the retry queue,
   * so anything reported here lands in the same report as everything else.
   */
  function log(level, message) {
    var sink = window.__dshLog;
    if (typeof sink === 'function') { sink(level, message); }
  }

  // Each distinct finding is reported once. The wizard re-renders on every
  // keystroke elsewhere in the page, and a report that repeats itself is a
  // report nobody reads.
  var reported = {};
  function report(level, message) {
    if (reported[message] === true) return;
    reported[message] = true;
    log(level, message);
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
   * The step's modal surface: a body child that is not #root and that opens with
   * the step rail. The rail is an <aside> whose first element is an <h2> holding
   * the wizard's title, in both the checklist and the summary it leads to.
   *
   * Scoping to body children other than #root is what keeps the app's own
   * sidebar out of reach: it is inside #root, and #root is inert precisely
   * because the step took it.
   */
  function stepSurface() {
    var root = appRoot();
    var body = document.body;
    if (body === null) return null;
    var nodes = body.children;
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      if (node === root || node.querySelector === undefined) continue;
      if (node.querySelector('aside h2') !== null) return node;
    }
    return null;
  }

  /**
   * The first enabled, text-labelled, non-menu button inside `scope`.
   *
   * The wizard's surface carries four kinds of button and only two of them are
   * exits: the language menu (`aria-haspopup`), the icon-only close control (no
   * text), and the per-task "configure"/"skip" row. All three are excluded here
   * or by the caller's scope, because clicking a task row would open a settings
   * page mid-dismissal.
   *
   * @returns the clicked label, or null when `scope` holds no action.
   */
  function clickAction(scope) {
    var buttons = scope.querySelectorAll('button');
    for (var i = 0; i < buttons.length; i++) {
      var button = buttons[i];
      if (button.disabled) continue;
      if (button.getAttribute('aria-haspopup') !== null) continue;
      var label = (button.textContent || '').replace(/s+/g, ' ').trim();
      if (label === '') continue;
      // The label is remembered on the node, so a re-render cannot click the
      // same button twice, while a different label is still free to be clicked.
      if (label === button.getAttribute(CLICKED)) continue;
      button.setAttribute(CLICKED, label);
      button.click();
      return label;
    }
    return null;
  }

  /**
   * The step's own action, found by the shape of the step rather than its copy.
   *
   * Two shapes exist over the wizard's life:
   *
   *   checklist -> <footer><button>skip all</button><span>n / 4</span></footer>
   *   summary   -> <div><span/><h1>title</h1><p/><button>start using</button></div>
   *
   * The footer is searched first because it only exists on the checklist; the
   * summary is then found by its heading, whose block holds the single primary
   * action. Searching the whole surface instead would reach the task rows.
   *
   * @returns the clicked label, or null when neither shape is present.
   */
  function clickStepAction(surface) {
    var footer = surface.querySelector('footer');
    if (footer !== null) {
      var fromFooter = clickAction(footer);
      if (fromFooter !== null) return fromFooter;
    }

    var headings = surface.querySelectorAll('h1');
    for (var i = 0; i < headings.length; i++) {
      var block = headings[i].parentNode;
      if (block === null || block === undefined) continue;
      var fromBlock = clickAction(block);
      if (fromBlock !== null) return fromBlock;
    }
    return null;
  }

  /** Compact description of what the surface offers, for the report. */
  function describeButtons(surface) {
    var buttons = surface.querySelectorAll('button');
    var parts = [];
    for (var i = 0; i < buttons.length; i++) {
      var button = buttons[i];
      var label = (button.textContent || '').replace(/s+/g, ' ').trim();
      parts.push(
        '[' + (label === '' ? '-' : label.slice(0, 16)) +
        (button.getAttribute('aria-haspopup') !== null ? '|menu' : '') +
        (button.disabled ? '|disabled' : '') + ']'
      );
    }
    return 'buttons=' + buttons.length + ' ' + parts.join('');
  }

  function run() {
    var surface = stepSurface();
    if (surface === null) return;

    // Reported whether or not the gate opens: "no surface" and "surface but not
    // inert" are different bugs, and only one of them is ours to fix.
    var owns = stepOwnsScreen();
    report('info', 'onboarding: surface seen inert=' + owns + ' ' + describeButtons(surface));
    if (!owns) return;

    var label = clickStepAction(surface);
    if (label === null) {
      report('warn', 'onboarding: no action matched on this surface');
      return;
    }
    report('info', "onboarding: clicked '" + label + "'");
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
  // so this cannot be a one-shot. The observer callback stays cheap: the body
  // scan is a handful of children, and only a step that owns the screen earns a
  // button walk.
  var observer = new MutationObserver(schedule);
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
