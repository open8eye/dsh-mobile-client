#!/usr/bin/env node
// Behavioural test for the onboarding guard in
// app/lib/core/browser/onboarding_script.dart.
//
// That script reaches into DSH's own DOM and clicks its buttons, so "the strings
// look right" is not good enough: it has to act on the wizard and on nothing
// else. There is no browser in this loop, so the script is run here against a
// hand-rolled stub of just the DOM surface it touches.
//
//   node tools/onboarding_check.mjs
//
// Exits non-zero on the first disagreement.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const DART = join(ROOT, 'app/lib/core/browser/onboarding_script.dart');

const match = /r'''([\s\S]*?)'''/.exec(readFileSync(DART, 'utf8'));
if (!match) {
  console.error('could not find the onboarding source in ' + DART);
  process.exit(2);
}
const SOURCE = match[1];

let failures = 0;
let checks = 0;

function check(label, actual, expected) {
  checks++;
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    failures++;
    console.error('FAIL ' + label + '\n  actual:   ' + JSON.stringify(actual) +
      '\n  expected: ' + JSON.stringify(expected));
  }
}

/** Just enough element for the script: tag search, text, clicks. */
class El {
  constructor(tag) {
    this.tagName = tag.toUpperCase();
    this.children = [];
    this.attrs = {};
    this.text = '';
    this.disabled = false;
    this.inert = false;
    this.clicks = 0;
  }
  append(child) {
    this.children.push(child);
    return child;
  }
  setAttribute(key, value) {
    this.attrs[key] = value;
  }
  getAttribute(key) {
    return Object.prototype.hasOwnProperty.call(this.attrs, key) ? this.attrs[key] : null;
  }
  get textContent() {
    return this.text + this.children.map((child) => child.textContent).join('');
  }
  click() {
    this.clicks++;
  }
  querySelector(selector) {
    return this.querySelectorAll(selector)[0] ?? null;
  }
  querySelectorAll(selector) {
    const wanted = selector.toUpperCase();
    const found = [];
    const walk = (node) => {
      for (const child of node.children) {
        if (child.tagName === wanted) found.push(child);
        walk(child);
      }
    };
    walk(this);
    return found;
  }
}

/**
 * Boot the real script against a stub page.
 *
 * @param inert - whether #root is inert, which is the whole gate.
 * @returns the fake document, the wizard surface, its buttons, and a way to
 *   deliver the mutations that would follow a click.
 */
function boot({ inert, withWizard = true, skipAllDisabled = false }) {
  const body = new El('body');
  const root = new El('div');
  root.id = 'root';
  root.inert = inert;
  body.append(root);

  let surface = null;
  let skipAll = null;
  let close = null;
  if (withWizard) {
    surface = body.append(new El('div'));
    const aside = surface.append(new El('aside'));
    aside.append(new El('h2'));
    const footer = surface.append(new El('footer'));
    skipAll = footer.append(new El('button'));
    skipAll.text = '跳过全部';
    skipAll.disabled = skipAllDisabled;
    // The close control renders an icon and no text, exactly like the real one.
    close = surface.append(new El('button'));
    close.text = '';
  }

  const document = {
    body,
    getElementById: (id) => (id === 'root' ? root : null),
    addEventListener: () => {},
  };

  let notify = null;
  class MutationObserver {
    constructor(callback) {
      notify = callback;
    }
    observe() {}
  }

  // Immediate: the script debounces through setTimeout, and the test wants the
  // work done by the time a mutation is delivered.
  const setTimeout = (fn) => {
    fn();
    return 0;
  };

  new Function('document', 'MutationObserver', 'setTimeout', SOURCE)(
    document,
    MutationObserver,
    setTimeout,
  );

  return { body, root, surface, skipAll, close, mutate: () => notify && notify() };
}

// An ordinary page with no wizard is left completely alone.
{
  const page = boot({ inert: false, withWizard: false });
  page.mutate();
  check('a page with no onboarding step survives boot', page.body.children.length, 1);
}

// A dialog is only touched while an onboarding step owns the screen.
{
  const page = boot({ inert: false });
  page.mutate();
  check('#root not inert means the wizard is not ours to touch', page.skipAll.clicks, 0);
}

// The wizard's own text action is clicked, and the icon-only control is not.
{
  const page = boot({ inert: true });
  check('the text action is clicked once on mount', page.skipAll.clicks, 1);
  check('the icon-only close control is left alone', page.close.clicks, 0);

  // Re-rendering the same label must not click it a second time.
  page.mutate();
  page.mutate();
  check('the same label is never clicked twice', page.skipAll.clicks, 1);

  // The wizard then shows its summary, whose action carries a different label.
  page.skipAll.text = '开始体验';
  page.mutate();
  check('a new label is still free to be clicked', page.skipAll.clicks, 2);
}

// A disabled action is left for the wizard to re-enable: "start using" is
// disabled while the acknowledgement is being saved.
{
  const page = boot({ inert: true, skipAllDisabled: true });
  page.mutate();
  check('a disabled action is not clicked', page.skipAll.clicks, 0);

  // Re-enabling it is all it takes for the click to land.
  page.skipAll.disabled = false;
  page.mutate();
  check('a re-enabled action is clicked', page.skipAll.clicks, 1);
}

// An unrecognised surface is left alone rather than guessed at.
{
  const page = boot({ inert: true, withWizard: false });
  const stranger = page.body.append(new El('div'));
  const dialog = stranger.append(new El('div'));
  const button = dialog.append(new El('button'));
  button.text = 'Delete everything';
  page.mutate();
  check('an unrelated dialog is never clicked', button.clicks, 0);
}

if (failures > 0) {
  console.error('\n' + failures + ' of ' + checks + ' checks failed');
  process.exit(1);
}
console.log('onboarding guard: ' + checks + ' checks passed');
