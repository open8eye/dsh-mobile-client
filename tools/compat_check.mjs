#!/usr/bin/env node
// Differential test for the browser shims in app/lib/core/browser/compat_script.dart.
//
// The shims exist because a phone can end up on an engine that parses the DSH
// bundle but lacks the runtime APIs it calls. Shipping a shim that is subtly
// wrong would be worse than shipping none, and there is no Android device in
// this loop, so the shims are checked here against the real implementations the
// running Node happens to provide: remove the native one, install ours, compare.
//
//   node tools/compat_check.mjs
//
// Exits non-zero on the first disagreement.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const DART = join(ROOT, 'app/lib/core/browser/compat_script.dart');

const match = /r'''([\s\S]*?)'''/.exec(readFileSync(DART, 'utf8'));
if (!match) {
  console.error('could not find the shim source in ' + DART);
  process.exit(2);
}
const SOURCE = match[1];

let failures = 0;
let checks = 0;

function check(label, actual, expected) {
  checks++;
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) {
    failures++;
    console.error('FAIL ' + label + '\n  shim:   ' + a + '\n  native: ' + b);
  }
}

async function checkAsync(label, run) {
  checks++;
  try {
    const [shim, native] = await run();
    const a = JSON.stringify(shim);
    const b = JSON.stringify(native);
    if (a !== b) {
      failures++;
      console.error('FAIL ' + label + '\n  shim:   ' + a + '\n  native: ' + b);
    }
  } catch (error) {
    failures++;
    console.error('FAIL ' + label + ' threw: ' + error);
  }
}

// --- capture the real implementations, then take them away ----------------

const natives = {
  'Object.hasOwn': Object.hasOwn,
  'Array.prototype.at': Array.prototype.at,
  'String.prototype.at': String.prototype.at,
  'String.prototype.replaceAll': String.prototype.replaceAll,
  'Promise.withResolvers': Promise.withResolvers,
  'Promise.try': Promise.try,
  'AbortSignal.any': AbortSignal.any,
  'AbortSignal.timeout': AbortSignal.timeout,
  'Array.prototype.findLast': Array.prototype.findLast,
  'Array.prototype.findLastIndex': Array.prototype.findLastIndex,
  'Array.prototype.toReversed': Array.prototype.toReversed,
  'Array.prototype.toSorted': Array.prototype.toSorted,
  'Array.prototype.with': Array.prototype.with,
  'String.prototype.toWellFormed': String.prototype.toWellFormed,
  'String.prototype.isWellFormed': String.prototype.isWellFormed,
  'Object.groupBy': Object.groupBy,
  'Map.groupBy': Map.groupBy,
  'Set.prototype.union': Set.prototype.union,
  'Set.prototype.intersection': Set.prototype.intersection,
  'Set.prototype.difference': Set.prototype.difference,
  'Set.prototype.symmetricDifference': Set.prototype.symmetricDifference,
  'Set.prototype.isSubsetOf': Set.prototype.isSubsetOf,
  'Set.prototype.isSupersetOf': Set.prototype.isSupersetOf,
  'Set.prototype.isDisjointFrom': Set.prototype.isDisjointFrom,
  'URL.parse': URL.parse,
  'URL.canParse': URL.canParse,
  'ArrayBuffer.prototype.transfer': ArrayBuffer.prototype.transfer,
  'ArrayBuffer.prototype.transferToFixedLength': ArrayBuffer.prototype.transferToFixedLength,
};

// The whole method here is differential: remove the real implementation, put
// ours in its place, compare. That needs a Node new enough to *have* every
// reference implementation, so say so plainly instead of failing obscurely.
const unavailable = Object.keys(natives).filter((key) => typeof natives[key] !== 'function');
if (unavailable.length) {
  console.error('this Node is too old to serve as a reference: ' + unavailable.join(', '));
  console.error('use Node 24 or newer, e.g. npx -y node@24 tools/compat_check.mjs');
  process.exit(2);
}

const remove = (target, name) => {
  try { delete target[name]; } catch { /* fall through to the check below */ }
  if (target[name] !== undefined) {
    Object.defineProperty(target, name, {
      value: undefined, writable: true, configurable: true,
    });
  }
};

for (const key of Object.keys(natives)) {
  const parts = key.split('.');
  const name = parts.pop();
  let target = globalThis;
  for (const part of parts) target = target[part];
  remove(target, name);
  if (target[name] !== undefined) {
    console.error('could not remove ' + key + '; the test would prove nothing');
    process.exit(2);
  }
}

// Symbol.dispose is a non-configurable well-known symbol, so it cannot be
// taken away. The shim must therefore leave it alone, which is what the
// Symbol checks at the bottom assert.
const nativeSymbolDispose = Symbol.dispose;

// crypto.randomUUID and navigator.clipboard are the insecure-origin pair.
const nativeRandomUUID = crypto.randomUUID;
Object.defineProperty(crypto, 'randomUUID', {
  value: undefined, writable: true, configurable: true,
});
const nativeClipboard = navigator.clipboard;
Object.defineProperty(navigator, 'clipboard', {
  value: undefined, writable: true, configurable: true,
});

// --- the browser bits the shim touches ------------------------------------

const copied = [];

globalThis.window = globalThis;
// The shim runs at document-start, before the Flutter bridge exists, so it
// parks its findings on a global that DiagnosticsScript forwards later.
globalThis.dshDiag = { log: () => { throw new Error('the bridge does not exist yet'); } };
globalThis.document = {
  body: { appendChild() {}, removeChild() {} },
  createElement() {
    return {
      style: {},
      value: '',
      setAttribute() {},
      select() {},
    };
  },
  execCommand(command) {
    copied.push(command);
    return true;
  },
};

// --- install the shims ----------------------------------------------------

// eslint-disable-next-line no-new-func
new Function(SOURCE)();

const parked = globalThis.__dshCompatReport || [];
const report = parked.join(' | ');

// --- compare --------------------------------------------------------------

check('the report is parked on the channel DiagnosticsScript reads', parked.length > 0, true);
check('the shim survives the bridge not existing yet', true, true);
check('reports the two that broke the field', /Promise\.withResolvers/.test(report) &&
  /AbortSignal\.any/.test(report), true);

check('Object.hasOwn', [
  Object.hasOwn({ a: 1 }, 'a'),
  Object.hasOwn({ a: 1 }, 'b'),
  Object.hasOwn({ a: 1 }, 'toString'),
  Object.hasOwn(Object.create({ a: 1 }), 'a'),
], [
  natives['Object.hasOwn']({ a: 1 }, 'a'),
  natives['Object.hasOwn']({ a: 1 }, 'b'),
  natives['Object.hasOwn']({ a: 1 }, 'toString'),
  natives['Object.hasOwn'](Object.create({ a: 1 }), 'a'),
]);

check('Object.hasOwn throws on null like the real one', (() => {
  const run = (fn) => { try { fn(); return 'no throw'; } catch (e) { return e.name; } };
  return [run(() => Object.hasOwn(null, 'a')), run(() => natives['Object.hasOwn'](null, 'a'))];
})(), [
  (() => { try { natives['Object.hasOwn'](null, 'a'); return 'no throw'; } catch (e) { return e.name; } })(),
  (() => { try { natives['Object.hasOwn'](null, 'a'); return 'no throw'; } catch (e) { return e.name; } })(),
]);

check('Array.prototype.at / String.prototype.at', [
  [1, 2, 3].at(0),
  [1, 2, 3].at(-1),
  [1, 2, 3].at(3),
  [1, 2, 3].at(-4),
  [1, 2, 3].at('1'),
  [1, 2, 3].at(NaN),
  'abc'.at(-1),
  'abc'.at(9),
], [
  natives['Array.prototype.at'].call([1, 2, 3], 0),
  natives['Array.prototype.at'].call([1, 2, 3], -1),
  natives['Array.prototype.at'].call([1, 2, 3], 3),
  natives['Array.prototype.at'].call([1, 2, 3], -4),
  natives['Array.prototype.at'].call([1, 2, 3], '1'),
  natives['Array.prototype.at'].call([1, 2, 3], NaN),
  natives['String.prototype.at'].call('abc', -1),
  natives['String.prototype.at'].call('abc', 9),
]);

check('String.prototype.replaceAll', [
  'a-b-c'.replaceAll('-', '+'),
  'abc'.replaceAll('', '-'),
  'a.b'.replaceAll('.', '/'),
  'aaa'.replaceAll('a', (m, i) => String(i)),
  'abc'.replaceAll(/b/g, 'X'),
], [
  natives['String.prototype.replaceAll'].call('a-b-c', '-', '+'),
  natives['String.prototype.replaceAll'].call('abc', '', '-'),
  natives['String.prototype.replaceAll'].call('a.b', '.', '/'),
  natives['String.prototype.replaceAll'].call('aaa', 'a', (m, i) => String(i)),
  natives['String.prototype.replaceAll'].call('abc', /b/g, 'X'),
]);

check('String.prototype.replaceAll rejects a non-global RegExp', (() => {
  const run = (fn) => { try { fn(); return 'no throw'; } catch (e) { return e.name; } };
  return [run(() => 'abc'.replaceAll(/b/, 'X'))];
})(), [
  (() => { try { natives['String.prototype.replaceAll'].call('abc', /b/, 'X'); return 'no throw'; } catch (e) { return e.name; } })(),
]);

await checkAsync('Promise.withResolvers', async () => {
  const a = Promise.withResolvers();
  const b = natives['Promise.withResolvers'].call(Promise);
  const settle = async (handle) => {
    setTimeout(() => handle.resolve('value'), 0);
    return handle.promise;
  };
  return [await settle(a), await settle(b)];
});

await checkAsync('Promise.withResolvers rejects', async () => {
  const run = async (factory) => {
    const handle = factory();
    setTimeout(() => handle.reject(new Error('nope')), 0);
    try { await handle.promise; return 'resolved'; } catch (e) { return e.message; }
  };
  return [
    await run(Promise.withResolvers),
    await run(() => natives['Promise.withResolvers'].call(Promise)),
  ];
});

await checkAsync('Promise.try', async () => {
  const shim = await Promise.try((a, b) => a + b, 1, 2);
  const native = await natives['Promise.try'].call(Promise, (a, b) => a + b, 1, 2);
  return [shim, native];
});

await checkAsync('Promise.try rejects on a synchronous throw', async () => {
  const run = async (fn) => {
    try { await fn(() => { throw new Error('boom'); }); return 'resolved'; }
    catch (e) { return e.message; }
  };
  return [
    await run(Promise.try),
    await run((fn) => natives['Promise.try'].call(Promise, fn)),
  ];
});

await checkAsync('AbortSignal.any', async () => {
  const run = async (any) => {
    const first = new AbortController();
    const second = new AbortController();
    const signal = any([first.signal, second.signal]);
    const before = signal.aborted;
    second.abort();
    await new Promise((resolve) => setTimeout(resolve, 0));
    return [before, signal.aborted];
  };
  return [await run(AbortSignal.any), await run(natives['AbortSignal.any'])];
});

await checkAsync('AbortSignal.any with an already-aborted input', async () => {
  const run = async (any) => {
    const dead = new AbortController();
    dead.abort();
    return any([dead.signal, new AbortController().signal]).aborted;
  };
  return [await run(AbortSignal.any), await run(natives['AbortSignal.any'])];
});

await checkAsync('AbortSignal.timeout fires', async () => {
  const run = async (timeout) => {
    const signal = timeout(1);
    await new Promise((resolve) => setTimeout(resolve, 25));
    return [signal.aborted, signal.reason && signal.reason.name];
  };
  return [await run(AbortSignal.timeout), await run(natives['AbortSignal.timeout'])];
});

check('Array.prototype.findLast / findLastIndex', [
  [1, 2, 3, 4].findLast((n) => n % 2 === 1),
  [1, 2, 3, 4].findLast((n) => n > 9),
  [1, 2, 3, 4].findLastIndex((n) => n % 2 === 0),
  [1, 2, 3, 4].findLastIndex((n) => n > 9),
], [
  natives['Array.prototype.findLast'].call([1, 2, 3, 4], (n) => n % 2 === 1),
  natives['Array.prototype.findLast'].call([1, 2, 3, 4], (n) => n > 9),
  natives['Array.prototype.findLastIndex'].call([1, 2, 3, 4], (n) => n % 2 === 0),
  natives['Array.prototype.findLastIndex'].call([1, 2, 3, 4], (n) => n > 9),
]);

check('Array.prototype.toReversed / toSorted do not mutate', (() => {
  const source = [3, 1, 2];
  const reversed = source.toReversed();
  const sorted = source.toSorted((a, b) => a - b);
  return [reversed, sorted, source];
})(), [
  natives['Array.prototype.toReversed'].call([3, 1, 2]),
  natives['Array.prototype.toSorted'].call([3, 1, 2], (a, b) => a - b),
  [3, 1, 2],
]);

check('Array.prototype.with', [
  [1, 2, 3].with(0, 'a'),
  [1, 2, 3].with(-1, 'z'),
  [1, 2, 3].with(NaN, 'n'),
], [
  natives['Array.prototype.with'].call([1, 2, 3], 0, 'a'),
  natives['Array.prototype.with'].call([1, 2, 3], -1, 'z'),
  natives['Array.prototype.with'].call([1, 2, 3], NaN, 'n'),
]);

check('Array.prototype.with rejects an out-of-range index', (() => {
  const run = (fn) => { try { fn(); return 'no throw'; } catch (e) { return e.name; } };
  return [
    run(() => [1, 2, 3].with(3, 'x')),
    run(() => [1, 2, 3].with(-4, 'x')),
  ];
})(), [
  (() => { try { natives['Array.prototype.with'].call([1, 2, 3], 3, 'x'); return 'no throw'; } catch (e) { return e.name; } })(),
  (() => { try { natives['Array.prototype.with'].call([1, 2, 3], -4, 'x'); return 'no throw'; } catch (e) { return e.name; } })(),
]);

check('String.prototype.toWellFormed / isWellFormed', [
  'a\uD800b'.toWellFormed(),
  'a\uDC00b'.toWellFormed(),
  '\uD83D\uDE00'.toWellFormed(),
  'a\uD800b'.isWellFormed(),
  '\uD83D\uDE00'.isWellFormed(),
  'plain'.isWellFormed(),
], [
  natives['String.prototype.toWellFormed'].call('a\uD800b'),
  natives['String.prototype.toWellFormed'].call('a\uDC00b'),
  natives['String.prototype.toWellFormed'].call('\uD83D\uDE00'),
  natives['String.prototype.isWellFormed'].call('a\uD800b'),
  natives['String.prototype.isWellFormed'].call('\uD83D\uDE00'),
  natives['String.prototype.isWellFormed'].call('plain'),
]);

check('Object.groupBy', (() => {
  const items = [1, 2, 3, 4, 5];
  const fn = (n) => (n % 2 ? 'odd' : 'even');
  const shim = Object.groupBy(items, fn);
  const native = natives['Object.groupBy'](items, fn);
  return [
    Object.keys(shim).sort(),
    shim.odd,
    shim.even,
    Object.getPrototypeOf(shim) === null,
    Object.keys(native).sort(),
    Object.getPrototypeOf(native) === null,
  ];
})(), (() => {
  const items = [1, 2, 3, 4, 5];
  const fn = (n) => (n % 2 ? 'odd' : 'even');
  const native = natives['Object.groupBy'](items, fn);
  return [
    Object.keys(native).sort(),
    native.odd,
    native.even,
    Object.getPrototypeOf(native) === null,
    Object.keys(native).sort(),
    Object.getPrototypeOf(native) === null,
  ];
})());

check('Map.groupBy', (() => {
  const items = [1, 2, 3, 4, 5];
  const fn = (n) => (n % 2 ? 'odd' : 'even');
  const shim = Map.groupBy(items, fn);
  const native = natives['Map.groupBy'](items, fn);
  return [
    [...shim.keys()].sort(),
    shim.get('odd'),
    shim.get('even'),
    [...native.keys()].sort(),
  ];
})(), (() => {
  const items = [1, 2, 3, 4, 5];
  const fn = (n) => (n % 2 ? 'odd' : 'even');
  const native = natives['Map.groupBy'](items, fn);
  return [
    [...native.keys()].sort(),
    native.get('odd'),
    native.get('even'),
    [...native.keys()].sort(),
  ];
})());

check('Set.prototype algebra', (() => {
  const left = new Set([1, 2, 3]);
  const right = new Set([3, 4]);
  return [
    [...left.union(right)].sort(),
    [...left.intersection(right)].sort(),
    [...left.difference(right)].sort(),
    [...left.symmetricDifference(right)].sort(),
    left.isSubsetOf(new Set([1, 2, 3, 4])),
    left.isSupersetOf(new Set([1, 2])),
    left.isDisjointFrom(new Set([9])),
    [...left].sort(),
  ];
})(), (() => {
  const left = new Set([1, 2, 3]);
  const right = new Set([3, 4]);
  return [
    [...natives['Set.prototype.union'].call(left, right)].sort(),
    [...natives['Set.prototype.intersection'].call(left, right)].sort(),
    [...natives['Set.prototype.difference'].call(left, right)].sort(),
    [...natives['Set.prototype.symmetricDifference'].call(left, right)].sort(),
    natives['Set.prototype.isSubsetOf'].call(left, new Set([1, 2, 3, 4])),
    natives['Set.prototype.isSupersetOf'].call(left, new Set([1, 2])),
    natives['Set.prototype.isDisjointFrom'].call(left, new Set([9])),
    [...left].sort(),
  ];
})());

check('URL.parse / URL.canParse', (() => {
  const good = URL.parse('https://example.com/dsh/?token=x');
  const relative = URL.parse('/a', 'https://example.com');
  const bad = URL.parse('not a url at all');
  return [
    good && good.href,
    relative && relative.href,
    bad,
    URL.canParse('https://example.com'),
    URL.canParse('not a url at all'),
  ];
})(), (() => {
  const good = natives['URL.parse'].call(URL, 'https://example.com/dsh/?token=x');
  const relative = natives['URL.parse'].call(URL, '/a', 'https://example.com');
  const bad = natives['URL.parse'].call(URL, 'not a url at all');
  return [
    good && good.href,
    relative && relative.href,
    bad,
    natives['URL.canParse'].call(URL, 'https://example.com'),
    natives['URL.canParse'].call(URL, 'not a url at all'),
  ];
})());

// The shim cannot make a resizable buffer, so only the fixed-length variant is
// compared exactly; transfer() is checked for the bytes it hands back.
// Called with .call() on purpose: both the real method and the shim read the
// buffer off `this`, and an unbound call would test neither.
const describeTransfer = (fn) => {
  const shorter = fn.call(new Uint8Array([1, 2, 3, 4]).buffer, 2);
  const longer = fn.call(new Uint8Array([9, 8]).buffer, 5);
  const same = fn.call(new Uint8Array([7]).buffer);
  const detached = (() => {
    const buffer = new Uint8Array([1]).buffer;
    fn.call(buffer, 1);
    return buffer.byteLength;
  })();
  return [
    [...new Uint8Array(shorter)],
    [...new Uint8Array(longer)],
    [...new Uint8Array(same)],
    detached,
  ];
};

check('ArrayBuffer.prototype.transferToFixedLength',
  describeTransfer(ArrayBuffer.prototype.transferToFixedLength),
  describeTransfer(natives['ArrayBuffer.prototype.transferToFixedLength']));

check('ArrayBuffer.prototype.transfer',
  describeTransfer(ArrayBuffer.prototype.transfer),
  describeTransfer(natives['ArrayBuffer.prototype.transfer']));

check('crypto.randomUUID shape', (() => {
  const value = crypto.randomUUID();
  return [
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value),
    value === crypto.randomUUID(),
    /^[0-9a-f-]{36}$/.test(nativeRandomUUID.call(crypto)),
  ];
})(), [true, false, true]);

await checkAsync('navigator.clipboard.writeText uses the fallback', async () => {
  const shim = await navigator.clipboard.writeText('hello').then(() => copied.join(','));
  return [shim, 'copy'];
});

// It could not be removed, so the shim must have reported it as native and
// left the real well-known symbol in place.
check('Symbol.dispose is left untouched', Symbol.dispose === nativeSymbolDispose, true);
check('Symbol.dispose is not claimed as shimmed', /Symbol\.dispose/.test(report), false);

// --- restore --------------------------------------------------------------

for (const [key, value] of Object.entries(natives)) {
  const parts = key.split('.');
  const name = parts.pop();
  let target = globalThis;
  for (const part of parts) target = target[part];
  Object.defineProperty(target, name, { value, writable: true, configurable: true });
}
Object.defineProperty(crypto, 'randomUUID', {
  value: nativeRandomUUID, writable: true, configurable: true,
});
if (nativeClipboard !== undefined) {
  Object.defineProperty(navigator, 'clipboard', {
    value: nativeClipboard, writable: true, configurable: true,
  });
}
Object.defineProperty(Symbol, 'dispose', {
  value: nativeSymbolDispose, writable: false, configurable: false,
});

console.log(checks + ' checks, ' + failures + ' failed');
console.log('report from the shim: ' + report);
process.exit(failures === 0 ? 0 : 1);
