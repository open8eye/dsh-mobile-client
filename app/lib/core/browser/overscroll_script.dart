/// Stops a horizontal drag from turning into a history navigation.
///
/// Chromium fires its "swipe to go back" gesture on a horizontal *overscroll*:
/// drag right when the scroller under the finger is already at its start, and
/// the engine treats the leftover movement as a back gesture. DSH's shell is a
/// horizontally scrollable single-page app, so a slightly diagonal swipe while
/// reading is enough to trigger it — and being thrown onto the previous page
/// mid-task is the accident this prevents.
///
/// `overscroll-behavior-x: none` tells the engine not to hand that overscroll
/// to the browser, which is the documented way to opt out. The `y` axis uses
/// `contain` rather than `none`: it still keeps pull-to-refresh from reloading
/// the shell, but leaves the bounce inside the scroller where it belongs.
///
/// This is the page half of the fix. The app half is the `PopScope` in
/// `home_shell.dart`, which claims the system back gesture; neither alone
/// covers both paths into a back navigation.
class OverscrollScript {
  const OverscrollScript._();

  /// Id of the injected `<style>`, so a second injection is a no-op.
  static const String styleId = 'dsh-no-overscroll-nav';

  static const String source = r'''
(function () {
  var ID = 'dsh-no-overscroll-nav';
  var CSS = 'html,body{overscroll-behavior-x:none;overscroll-behavior-y:contain}';

  function apply() {
    var head = document.head;
    if (!head) return false;
    if (document.getElementById(ID)) return true;
    var style = document.createElement('style');
    style.id = ID;
    style.textContent = CSS;
    head.appendChild(style);
    return true;
  }

  // At document start there is no <head> yet, so the style is placed the moment
  // one appears. The observer disconnects itself on the first success, and the
  // id check makes a second injection harmless.
  if (!apply() && document.documentElement) {
    var observer = new MutationObserver(function () {
      if (apply()) observer.disconnect();
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
  }
})();
''';
}
