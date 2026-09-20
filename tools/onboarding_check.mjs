#!/usr/bin/env node
// Behavioural test for the onboarding guard in
// app/lib/core/browser/onboarding_script.dart.
//
// That script reaches into DSH's own DOM and clicks its buttons, so "the strings
// look right" is not good enough. Its surface carries four kinds of button and
// only two of them are exits — clicking a task row or the language menu would be
// worse than doing nothing. There is no browser in this loop, so the script runs
// here against a hand-rolled stub of just the DOM it touches, shaped like the
// wizard's real markup:
//
//   <div class="layout">
//     <aside class="rail"><h2>…</h2>…</aside>
//     <main class="main">
//       <div class="topActions"><button aria-haspopup="menu">简体中文</button><button/>  <- icon
//       <div class="heading"><h1>…</h1><p>…</p></div>
//       <section class="task"><button>配置</button><button>跳过</button></section>
//       <footer><button>跳过全部</button><span>0 / 4</span></footer>
//     </main>
//   </div>
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

/** Just enough element for the script: descendant lookup, text, clicks. */
class El {
  constructor(tag) {
    this.tagName = tag.toUpperCase();
    this.children = [];
    this.attrs = {};
    this.text = '';
    this.disabled = false;
    this.inert = false;
    this.clicks = 0;
    this.parentNode = null;
  }
  append(child) {
    child.parentNode = this;
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
    const tags = selector.trim().split(/\s+/).map((tag) => tag.toUpperCase());
    const matches = (node, parts) => {
      if (node.tagName !== parts[parts.length - 1]) return false;
      let ancestor = node.parentNode;
      for (let i = parts.length - 2; i >= 0; i--) {
        while (ancestor !== null && ancestor.tagName !== parts[i]) ancestor = ancestor.parentNode;
        if (ancestor === null) return false;
        ancestor = ancestor.parentNode;
      }
      return true;
    };
    const found = [];
    const walk = (node) => {
      for (const child of node.children) {
        if (matches(child, tags)) found.push(child);
        walk(child);
      }
    };
    walk(this);
    return found;
  }
}

const el = (tag, text = '') => {
  const node = new El(tag);
  node.text = text;
  return node;
};

/** The step rail, shared by both shapes. */
function buildRail(layout) {
  const rail = layout.append(el('aside'));
  rail.append(el('h2', '开始使用'));
  const step = rail.append(el('div'));
  step.append(el('span', '1'));
  step.append(el('span', '模型'));
}

/** The language menu and the icon-only close control, in that order. */
function buildTopActions(main) {
  const actions = main.append(el('div'));
  const language = actions.append(el('button', '简体中文'));
  language.setAttribute('aria-haspopup', 'menu');
  const close = actions.append(el('button'));
  return { language, close };
}

/**
 * Boot the real script against a stub page.
 *
 * @param inert - whether #root is inert, which is the whole gate.
 * @param shape - 'checklist', 'summary', 'stranger' or 'none'.
 * @returns the fake document, the wizard's controls, and a way to deliver the
 *   mutations that would follow a click.
 */
function boot({ inert, shape = 'checklist' }) {
  const body = new El('body');
  const root = el('div');
  root.id = 'root';
  root.inert = inert;
  body.append(root);

  let surface = null;
  let language = null;
  let close = null;
  let skipAll = null;
  let configure = null;
  let primary = null;
  let success = null;

  if (shape === 'checklist') {
    surface = body.append(el('div'));
    const layout = surface.append(el('div'));
    buildRail(layout);
    const main = layout.append(el('main'));
    const top = buildTopActions(main);
    language = top.language;
    close = top.close;
    const heading = main.append(el('div'));
    heading.append(el('h1', '开始使用'));
    heading.append(el('p', '只需几分钟。'));
    const task = main.append(el('section'));
    configure = task.append(el('button', '配置'));
    task.append(el('button', '跳过'));
    const footer = main.append(el('footer'));
    skipAll = footer.append(el('button', '跳过全部'));
    footer.append(el('span', '0 / 4 已完成'));
  } else if (shape === 'summary') {
    surface = body.append(el('div'));
    const layout = surface.append(el('div'));
    buildRail(layout);
    const main = layout.append(el('main'));
    const top = buildTopActions(main);
    language = top.language;
    close = top.close;
    success = main.append(el('div'));
    success.append(el('span'));
    success.append(el('h1', '已准备就绪'));
    success.append(el('p', '跳过的步骤之后仍可在设置中完成。'));
    primary = success.append(el('button', '开始体验'));
  } else if (shape === 'stranger') {
    surface = body.append(el('div'));
    const dialog = surface.append(el('div'));
    const button = dialog.append(el('button', 'Delete everything'));
    button.clicks = 0;
    primary = button;
  }

  const logs = [];
  const window = { __dshLog: (level, message) => logs.push(level + ': ' + message) };
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

  new Function('document', 'MutationObserver', 'setTimeout', 'window', SOURCE)(
    document,
    MutationObserver,
    setTimeout,
    window,
  );

  return {
    body,
    root,
    surface,
    layout: surface ? surface.children[0] : null,
    language,
    close,
    skipAll,
    configure,
    primary,
    success,
    logs,
    mutate: () => notify && notify(),
    /** Swap the checklist for the summary, the way the wizard does. */
    showSummary() {
      const main = this.layout.querySelector('main');
      main.children = main.children.filter((child) => child.tagName !== 'FOOTER');
      this.success = main.append(el('div'));
      this.success.append(el('span'));
      this.success.append(el('h1', '已准备就绪'));
      this.success.append(el('p', '跳过的步骤之后仍可在设置中完成。'));
      this.primary = this.success.append(el('button', '开始体验'));
    },
  };
}

// The checklist: only the footer's own action is clicked.
{
  const page = boot({ inert: true, shape: 'checklist' });
  check('the checklist skips all', page.skipAll.clicks, 1);
  check('the language menu is never clicked', page.language.clicks, 0);
  check('the icon-only close control is never clicked', page.close.clicks, 0);
  check('a per-task row button is never clicked', page.configure.clicks, 0);

  page.mutate();
  page.mutate();
  check('the same label is never clicked twice', page.skipAll.clicks, 1);
}

// The summary that follows: its own heading block holds the only action.
{
  const page = boot({ inert: true, shape: 'checklist' });
  page.showSummary();
  page.mutate();
  check('the summary starts using', page.primary.clicks, 1);
  check('the summary does not touch the language menu', page.language.clicks, 0);
  check('the summary does not touch the close control', page.close.clicks, 0);
}

// The gate: a surface that is not owned by an onboarding step is left alone.
{
  const page = boot({ inert: false, shape: 'checklist' });
  check('#root not inert means the wizard is not ours to touch', page.skipAll.clicks, 0);
  check(
    'the refusal is still reported, so the gate can be told apart from a miss',
    page.logs.some((line) => line.includes('surface seen inert=false')),
    true,
  );
}

// A disabled action is left for the wizard to re-enable: "start using" is
// disabled while the acknowledgement is being saved.
{
  const page = boot({ inert: true, shape: 'summary' });
  // Rebuild with the primary disabled before the first run, since boot runs the
  // script immediately.
  const held = boot({ inert: true, shape: 'none' });
  held.surface = held.body.append(el('div'));
  const layout = held.surface.append(el('div'));
  buildRail(layout);
  const main = layout.append(el('main'));
  const heading = main.append(el('div'));
  heading.append(el('h1', '已准备就绪'));
  const button = heading.append(el('button', '开始体验'));
  button.disabled = true;
  held.mutate();
  check('a disabled action is not clicked', button.clicks, 0);
  button.disabled = false;
  held.mutate();
  check('a re-enabled action is clicked', button.clicks, 1);
  check('the summary case above still clicked once', page.primary.clicks, 1);
}

// An unrecognised surface is left alone rather than guessed at.
{
  const page = boot({ inert: true, shape: 'stranger' });
  check('an unrelated dialog is never clicked', page.primary.clicks, 0);
}

// Nothing to do at all is not an error.
{
  const page = boot({ inert: true, shape: 'none' });
  page.mutate();
  check('a page with no step logs nothing', page.logs.length, 0);
}

// Every decision is legible from the report alone.
{
  const page = boot({ inert: true, shape: 'checklist' });
  check(
    'the surface and its buttons are described',
    // Five buttons, and only one of them is an exit: the language menu, the
    // icon-only close control, and two per-task rows are all excluded.
    page.logs.some((line) => line.includes('buttons=5') && line.includes('|menu')),
    true,
  );
  check(
    'the click is reported with the label it used',
    page.logs.some((line) => line.includes("clicked '跳过全部'")),
    true,
  );
}

if (failures > 0) {
  console.error('\n' + failures + ' of ' + checks + ' checks failed');
  process.exit(1);
}
console.log('onboarding guard: ' + checks + ' checks passed');
