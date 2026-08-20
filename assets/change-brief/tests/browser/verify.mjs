// Optional headless smoke test for rendered change briefs. Where it cannot run,
// these assertions fall to the numbered walk cases in the plan's Browser-Walk
// Inventory -- nothing in the shell suite or the render pipeline depends on it.
//
//   cd assets/change-brief/tests/browser && npm install && node verify.mjs
//
// Exit codes are three-valued on purpose: 0 every assertion passed, 1 an
// assertion failed, 2 no browser to run against. A skip that exited 0 would
// read as a pass in any wrapper that only looks at the status.
import { chromium } from 'playwright-core';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ASSETS = resolve(HERE, '../..');
const FIX = join(ASSETS, 'tests/fixtures');
const W = mkdtempSync(join(tmpdir(), 'brief-'));
// render_test.sh does `trap 'rm -rf "$W"' EXIT`; match it. Registered at the
// point of creation so it fires on every exit -- the no-browser skip below, an
// assertion failure, and a throw out of render() alike. Measured before this
// line existed: 55 leaked brief-* directories holding 1.1 GB.
process.on('exit', () => rmSync(W, { recursive: true, force: true }));

// render_test.sh pins the number of chk() calls this file CONTAINS. This pins
// the number it actually RUNS, which is a different guarantee: an assertion
// block wrapped in `if (false)`, commented out, or rewritten to compare a value
// to itself leaves the source count intact while the run silently covers less.
// Measured: `// 4. Inertness.\n{` -> `if (false) {` reported 26 passed, 0
// failed, exit 0. Keep this in step with render_test.sh's inventory pin; both
// move together, and so does the plan's Step 4 number.
const EXPECTED = 38;

let pass = 0, fail = 0;
const ok = m => { console.log('  PASS  ' + m); pass++; };
const no = (m, d) => { console.log('  FAIL  ' + m + ' :: ' + d); fail++; };
const chk = (m, got, want) =>
  JSON.stringify(got) === JSON.stringify(want) ? ok(m) : no(m, `expected ${JSON.stringify(want)} got ${JSON.stringify(got)}`);

// The harness's own smoke test, run before anything else, because every
// assertion in this file is worth exactly what chk is worth. Rewriting the
// comparison away -- `const chk = (m, got, want) => ok(m);` -- is one line, it
// leaves the source count and every pinned selector intact, and it is the worst
// failure this harness has: measured, a chk neutered that way certified a page
// firing four live requests to evil.example.invalid as `38 passed, 0 failed`,
// with the shell suite green alongside it.
//
// It reports by THROWING, not through no(). Reporting through no() would work
// while only chk is neutered, but it would go silent the moment no() is itself
// the broken thing -- and "the reporting path can be trusted" is the whole
// proposition being established here, so the check may not lean on any part of
// it. A throw needs neither helper: the process dies non-zero, with a message,
// before a single real assertion has run. Both directions are exercised, so a
// chk stubbed to always FAIL is caught by the same block.
//
// The counters are restored afterwards, so the canary costs nothing against
// EXPECTED: the suite is 38 assertions while the file holds 40 chk( call sites.
// render_test.sh pins both numbers, and they are meant to differ by exactly the
// two calls below.
{
  const p0 = pass, f0 = fail, say = console.log;
  let detected, reported;
  // A FAIL line printed by a healthy run teaches readers to skim past FAIL
  // lines, so the canary's own output is swallowed. finally, because a chk that
  // throws rather than returning must not leave the console muted.
  console.log = () => {};
  try {
    chk('canary: a mismatched pair must fail', 1, 2);
    detected = fail === f0 + 1 && pass === p0;
    chk('canary: a matching pair must pass', 1, 1);
    reported = pass === p0 + 1;
  } finally {
    console.log = say;
    pass = p0; fail = f0;
  }
  if (!detected || !reported) {
    throw new Error('harness self-test failed: a mismatched pair ' +
      (detected ? 'failed' : 'did NOT fail') + ' and a matching pair ' +
      (reported ? 'passed' : 'did NOT pass') +
      '. chk/ok/no are not reporting, so every assertion in this file is void.');
  }
}

function render(spec, plan, out) {
  const args = plan ? [spec, plan, '-o', out] : [spec, '-o', out];
  try {
    execFileSync(join(ASSETS, 'render.sh'), args, { stdio: 'pipe' });
  } catch (e) {
    // stdio:'pipe' swallows render.sh's diagnostics, and its message names the
    // real cause every time it refuses (CRLF input, unreadable plan, template
    // placeholder gone). Surfacing it turns "Command failed" into the answer.
    throw new Error(`render.sh failed for ${spec}:\n${e.stderr ? e.stderr.toString().trim() : e.message}`);
  }
  return out;
}

// Two launchers, most reproducible first. The managed build is the one
// `npx playwright install chromium` fetches, pinned to the playwright-core in
// package.json, so a run here means the same as a run anywhere. A system Google
// Chrome is the fallback that needs no download. The fallback is not
// hypothetical: on the machine this was written on the managed build is absent
// -- the cache holds chromium revision 1228 and playwright-core 1.62.1 asks for
// 1234 -- and the system Chrome answers.
const LAUNCHERS = [
  ['playwright chromium', {}],
  ['system chrome', { channel: 'chrome' }]
];

async function launch() {
  const why = [];
  for (const [label, opts] of LAUNCHERS) {
    try {
      return await chromium.launch(opts);
    } catch (e) {
      why.push(`  ${label}: ${String(e.message).split('\n')[0].trim()}`);
    }
  }
  // A stack trace here would name playwright's internals, not the one thing the
  // reader has to do about it.
  console.log('browser: skipped -- no usable browser on this machine.');
  console.log(why.join('\n'));
  console.log('\nInstall one of them, then re-run:');
  console.log('  npx playwright install chromium     # playwright\'s own pinned build');
  console.log('  ...or install Google Chrome         # used as-is, no download');
  console.log('\nWalk cases 1-11 in the plan cover the same ground by hand.');
  process.exit(2);
}

const browser = await launch();

async function probe(file) {
  const ctx = await browser.newContext();
  const p = await ctx.newPage();
  const errs = [], reqs = [];
  p.on('pageerror', e => errs.push(e.message));
  p.on('request', r => { if (!r.url().startsWith('file://')) reqs.push(r.url()); });
  await p.goto('file://' + file);
  // The page marks its own completion (Task 13). Waiting on that instead of a
  // fixed sleep is what distinguishes "still rendering" from "stalled", and it
  // is set on every path that ends the run -- including the ones that fail.
  await p.waitForSelector('[data-diagrams]', { timeout: 30000 });
  const r = await p.evaluate(() => ({
    banners: [...document.querySelectorAll('.integrity-banner')].map(b => b.textContent.slice(0, 40)),
    light: document.querySelectorAll('.mermaid-block .d-light svg').length,
    dark: document.querySelectorAll('.mermaid-block .d-dark svg').length,
    errBoxes: document.querySelectorAll('.mermaid-error').length,
    // Task 13's Critical: a payload init directive re-enabling htmlLabels builds
    // labels as HTML, which is how a live <img> reaches the document. Zero
    // <foreignObject> is the observable proof the secure list still holds.
    foreignObjects: document.querySelectorAll('foreignObject').length,
    // Mermaid leaves its temp container attached to <body> on every failure
    // exit; it carries mermaid's own error graphic, outside .shell, unclassed.
    orphans: document.querySelectorAll('[id^="dmmd-"], [id^="immd-"]').length,
    // themeCSS is concatenated verbatim into the emitted <style>. Counting live
    // <style> elements that carry a payload host is the only thing that sees it:
    // it needs no <foreignObject>, no <img>, and leaves the diagram rendering
    // normally, so every other probe here reads clean while it is wide open.
    styleBeacons: [...document.querySelectorAll('style')]
      .filter(n => n.isConnected && n.textContent.includes('evil.example.invalid')).length,
    diagramsState: document.documentElement.getAttribute('data-diagrams'),
    contentH1: document.querySelectorAll('#content h1').length,
    pending: document.querySelectorAll('.callout.pending').length,
    groups: [...document.querySelectorAll('.toc-group')].map(g => ({
      h2: g.querySelector('a.lvl2').textContent,
      kids: [...g.querySelectorAll('.kids a')].map(a => a.textContent)
    })),
    anchors: [...document.querySelectorAll('#content a')].map(a => ({ href: a.getAttribute('href'), host: a.host })),
    // Every index entry must resolve to its own heading. This runs after the
    // waitForSelector above, so the diagram chain has finished and every id the
    // library injects -- including the unnamespaced literals it does not
    // namespace per render -- is already in the document. Stated as the
    // spec-level property rather than as a vocabulary to reserve: it catches a
    // collision with any id, from any diagram type, in any future version of
    // the bundle, and it is the backstop for the payload-derived ids that the
    // template's `h-` prefix on heading ids cannot cover.
    deadAnchors: [...document.querySelectorAll('#toc a[data-target]')]
      .filter(a => {
        const t = document.getElementById(a.dataset.target);
        return !t || !/^H[23]$/.test(t.tagName);
      })
      .map(a => a.dataset.target),
    chips: document.querySelectorAll('.img-chip').length,
    pwn: window.__PWN === undefined ? null : window.__PWN,
    dagCaption: (document.querySelector('.dag-caption') || {}).textContent || null,
    // Anchored to .dag-caption's previous sibling, which IS the generated graph
    // box: the template inserts the box and then the caption before the same
    // anchor, so they are adjacent siblings. Selecting "the first .mermaid-block
    // whose data-src starts with flowchart" instead picks up spec.md's own
    // decorative `flowchart LR / A[Start] --> B[End]` on gate2 -- measured --
    // and reaches the real graph in the plan-region case only because that
    // fixture's own fence happens to be a sequenceDiagram.
    dagSrc: (() => {
      const cap = document.querySelector('.dag-caption');
      const box = cap && cap.previousElementSibling;
      return box && box.classList.contains('mermaid-block') ? (box.dataset.src || '') : '';
    })()
  }));
  await ctx.close();
  return { ...r, pageerrors: errs, offsite: reqs };
}

// 1. Gate 1: spec only.
{
  const f = render(join(FIX, 'spec.md'), null, join(W, 'g1.html'));
  const r = await probe(f);
  chk('gate1: no banners', r.banners, []);
  chk('gate1: pending callout rendered', r.pending, 1);
  chk('gate1: no content h1', r.contentH1, 0);
  chk('gate1: diagram in both themes', [r.light, r.dark], [1, 1]);
  chk('gate1: no offsite requests', r.offsite, []);
  chk('gate1: no page errors', r.pageerrors, []);
}

// 2. Gate 2: spec + plan. Graph must show only declared edges.
{
  const f = render(join(FIX, 'spec.md'), join(FIX, 'plan.md'), join(W, 'g2.html'));
  const r = await probe(f);
  chk('gate2: no banners', r.banners, []);
  chk('gate2: no pending callout', r.pending, 0);
  const plan = r.groups.find(g => g.h2 === 'Plan');
  chk('gate2: all three tasks under Plan', plan ? plan.kids.length : 0, 3);
  chk('gate2: dag caption present', typeof r.dagCaption === 'string', true);
  chk('gate2: spec diagram plus dag rendered', [r.light, r.dark], [2, 2]);
  // The comment above this block promised "only declared edges" while nothing
  // in the file read an edge. plan.md declares Task 2 -> Task 1 and Task 3 ->
  // Task 1, Task 99; Task 99 has no heading of its own, and the `Depends on:
  // Task 2` sitting in PROSE must not become an edge. The exact list is the
  // only form that says all three at once: a count passes with the wrong pair,
  // and a some() passes with an extra one alongside the right ones.
  chk('gate2: graph carries exactly the declared edges',
      (r.dagSrc.match(/^\s*T\d+ --> T\d+$/gm) || []).map(e => e.trim()),
      ['T1 --> T2', 'T1 --> T3']);
  chk('gate2: no page errors', r.pageerrors, []);
}

// 3. Broken diagram: one error box, the others still render.
{
  const f = render(join(FIX, 'broken-diagram.md'), null, join(W, 'broken.html'));
  const r = await probe(f);
  chk('broken: exactly one error box', r.errBoxes, 1);
  chk('broken: other diagrams still render', [r.light, r.dark], [2, 2]);
  chk('broken: no page errors', r.pageerrors, []);
}

// A spec carrying its own "## Plan" and its own task-shaped "### Task 1:" must
// not capture the sentinel, the index group, or the dependency graph. Five
// review rounds put the plan's tasks under a foreign heading; this pins it.
{
  const f = render(join(FIX, 'plan-region.md'), join(FIX, 'plan.md'), join(W, 'plan-region.html'));
  const r = await probe(f);
  // LAST matching group: plan-region.md deliberately carries its own "## Plan"
  // section, and the sentinel marker is stripped before data-toc is captured,
  // so both index groups are literally labelled "Plan".
  const plan = r.groups.filter(g => g.h2 === 'Plan').pop();
  chk('plan-region: tasks nest under Plan', plan ? plan.kids : null,
      ['Task 1: Alpha', 'Task 2: Beta', 'Task 3: Gamma']);
  chk('plan-region: spec task heading excluded from the Plan group',
      (plan ? plan.kids : []).some(k => /Example quoted/.test(k)), false);
  chk('plan-region: graph node emitted once per real task',
      (r.dagSrc.match(/^\s*T\d+\[/gm) || []).length, 3);
  // The property no static test can reach, and the reason this fixture carries a
  // sequence fence ahead of a "## Database" heading. Every index entry must still
  // resolve to its own heading after the diagrams have landed: a heading whose id
  // collides with one the library injects resolves to that node instead, silently,
  // and only when the diagram precedes it in document order. This page holds both
  // marker vocabularies -- the generated flowchart DAG and the sequence fence --
  // so it covers the whole family rather than one diagram type. Asserted HERE and
  // not in gate2, whose fixtures collide with nothing and would report [] with the
  // template's heading-id prefix deleted.
  chk('plan-region: every index entry resolves to its own heading', r.deadAnchors, []);
  chk('plan-region: no banners', r.banners, []);
  chk('plan-region: no page errors', r.pageerrors, []);
}

// 4. Inertness.
{
  const f = render(join(FIX, 'beacon.md'), null, join(W, 'beacon.html'));
  const r = await probe(f);
  chk('beacon: zero offsite requests', r.offsite, []);
  chk('beacon: remote image is a chip', r.chips, 1);
  chk('beacon: nothing executed', r.pwn, null);
  const hosts = r.anchors.map(a => a.host).filter(Boolean);
  chk('beacon: no anchor reaches a remote host', hosts, ['example.com']);
  const hrefs = r.anchors.map(a => a.href);
  chk('beacon: javascript and UNC hrefs demoted', hrefs.includes('javascript:window.__PWN=1'), false);
  chk('beacon: bare relative link kept', hrefs.includes('BLOCKS.md'), true);
  // Task 13's Critical, regression-tested in a real browser: the fence in this
  // fixture carries %%{init:{"flowchart":{"htmlLabels":true}}}%% and an <img>
  // node label. Both counts are zero only while the secure list holds.
  chk('beacon: directive cannot re-enable HTML labels', r.foreignObjects, 0);
  chk('beacon: directive cannot inject CSS into the emitted stylesheet', r.styleBeacons, 0);
  chk('beacon: no orphaned mermaid temp container', r.orphans, 0);
  chk('beacon: both directive fences still rendered in both themes', [r.light, r.dark], [2, 2]);
  chk('beacon: the run completed rather than stalling', r.diagramsState, 'done');
}

// 5. Dangling comment: content survives, nothing is lost.
{
  const f = render(join(FIX, 'comment-truncation.md'), null, join(W, 'ct.html'));
  const r = await probe(f);
  chk('comment: no content-lost banner', r.banners.filter(b => b.startsWith('Content lost')), []);
  chk('comment: later section survived', r.groups.some(g => g.h2 === 'Later Section'), true);
  chk('comment: pending callout survived', r.pending, 1);
}

// 6. Hostile title never becomes markup.
{
  const f = render(join(FIX, 'hostile-title.md'), null, join(W, 'ht.html'));
  const r = await probe(f);
  chk('hostile: no banners', r.banners, []);
  chk('hostile: no page errors', r.pageerrors, []);
}

await browser.close();
// Last, on the only path that reaches the summary: a block that threw never
// arrives here at all, which is louder still.
if (pass + fail !== EXPECTED) {
  no(`assertion inventory: ran ${pass + fail}`, `expected ${EXPECTED}`);
}
console.log(`\nbrowser: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
