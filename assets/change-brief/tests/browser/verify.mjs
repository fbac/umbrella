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
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
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
const EXPECTED = 44;

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
// EXPECTED: the suite is 44 assertions while the file holds 46 chk( call sites.
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
    // SVG anchors are anchors. The <a> a mermaid `click ... href` directive
    // builds carries xlink:href, where getAttribute('href') is null, and a.host
    // is undefined on every SVGAElement -- so the previous shape audited a
    // diagram full of live remote links as nothing at all, and reported the
    // same clean answer whether one was there or not. Both spellings are read.
    //
    // The target is resolved through `new URL(..., document.baseURI)` rather
    // than read off a.host, for the second half of the same blindness: data:,
    // vbscript: and javascript: all resolve to an EMPTY host -- three of the
    // five demotions BLOCKS.md promises -- so a check that filters on host
    // discards exactly those before comparing anything. The scheme sees them.
    anchors: [...document.querySelectorAll('#content a')].map(a => {
      const href = a.hasAttribute('href') ? a.getAttribute('href')
                 : (a.hasAttribute('xlink:href') ? a.getAttribute('xlink:href') : null);
      let scheme = null, host = null;
      if (href !== null) {
        try { const u = new URL(href, document.baseURI); scheme = u.protocol.slice(0, -1); host = u.host; }
        catch (e) { scheme = 'unparseable'; host = ''; }
      }
      const first = a.firstElementChild;
      return {
        href, scheme, host,
        svg: !!a.ownerSVGElement,
        // Which theme render the anchor sits in. Both are built up front, so a
        // sweep that ran on the light pass alone leaves the dark one live, and
        // a page-wide total cannot tell that apart from a clean page.
        slot: a.closest('.d-dark') ? 'dark' : (a.closest('.d-light') ? 'light' : 'doc'),
        // template.html demotes a rejected diagram target by stripping the
        // linking attributes and putting `label (href)` into an SVG <title> --
        // the same shape the markdown renderer gives a rejected link.
        demoted: first && first.tagName.toLowerCase() === 'title' ? first.textContent : null
      };
    }),
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
    // Mermaid emits arrowhead, crosshead, sequencenumber and filled-head -- and
    // clock, database, computer -- verbatim, so a page holding a LIGHT and a
    // DARK render of one diagram holds two elements sharing each of those ids.
    // url(#arrowhead) resolves to the first match in document order, always the
    // light pass, which in dark theme sits inside a display:none subtree, and a
    // marker that is not rendered paints nothing. Measured in Chrome before
    // template.html's nsIds() existed: the dark render lost every arrowhead and
    // every autonumber bubble outright while light kept both. Stated as "no id
    // appears twice" rather than as a list of names, so it covers whatever ids a
    // future bundle adds. The root <svg>'s own id is unique per render already,
    // which is exactly why nsIds() can and must leave that one alone.
    dupIds: (() => {
      const seen = new Set(), dup = new Set();
      for (const el of document.querySelectorAll('[id]')) {
        if (seen.has(el.id)) dup.add(el.id); else seen.add(el.id);
      }
      return [...dup].sort();
    })(),
    // The anti-vacuity half. dupIds is [] on any page that never held two
    // renders of a marker-bearing diagram, so the markers are counted beside it.
    // Matched namespaced OR bare -- `mmd-3-arrowhead` and `arrowhead` both --
    // so the count is identical with nsIds() present and with it deleted, and a
    // failure moves the duplicate list alone instead of both terms at once.
    markerIds: [...document.querySelectorAll('[id]')]
      .filter(e => /(^|-)(arrowhead|crosshead|sequencenumber|filled-head)$/.test(e.id)).length,
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

// probe()'s context takes the default viewport, which is wide enough that the
// property below cannot fail in it, so the narrow case needs a context of its
// own. Created probe()'s way rather than a second way: same newContext, same
// wait on the page's own completion marker rather than a sleep, same close. It
// carries none of probe()'s listeners because it asserts none of probe()'s
// properties -- inertness and page errors are covered on the fixtures above,
// and this page exists only to be measured at a width.
async function narrow(file, width) {
  const ctx = await browser.newContext({ viewport: { width, height: 800 } });
  const p = await ctx.newPage();
  await p.goto('file://' + file);
  await p.waitForSelector('[data-diagrams]', { timeout: 30000 });
  const r = await p.evaluate(() => {
    const de = document.documentElement, over = [];
    // Top AND bottom: the measured defect was present at every scroll offset,
    // and a sticky or absolutely positioned box can overflow at the bottom of a
    // page that measures clean at the top. The BODY is what is asserted on --
    // pre, table and .mermaid-block each own an overflow-x of their own on
    // purpose, so a check written against descendants would forbid the fixture.
    for (const y of [0, 1e6]) {
      window.scrollTo(0, y);
      if (de.scrollWidth > de.clientWidth) over.push([window.scrollY, de.scrollWidth, de.clientWidth]);
    }
    // Vacuity guard, and it has to be measured rather than counted: word-wrap
    // already breaks a line at a hyphen, so a 90-character hyphenated token
    // wraps unaided and proves nothing. Every run with no break opportunity in
    // it is laid out on a canvas in the font its own code span resolved to.
    // Unless one of them is wider than the viewport the page cannot overflow,
    // and then the measurement above passes whether the fix is there or not.
    // pre and table are skipped for the reason they are exempt in the CSS.
    const cv = document.createElement('canvas').getContext('2d');
    let widest = 0;
    for (const c of document.querySelectorAll('#content code')) {
      if (c.closest('pre, table')) continue;
      cv.font = getComputedStyle(c).font;
      for (const tok of c.textContent.match(/[^\s-]+/g) || []) {
        widest = Math.max(widest, cv.measureText(tok).width);
      }
    }
    return { overflows: over, tokenWiderThanViewport: widest > de.clientWidth };
  });
  await ctx.close();
  return r;
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
  // Every anchor by scheme AND host, not `.filter(Boolean)` over hosts, which
  // was the old shape. javascript:, data: and vbscript: all resolve to an empty
  // host, so a host filter throws away three of the five schemes BLOCKS.md
  // promises to demote before any comparison happens. Measured: with
  // `|| /^(ftp|data)$/i.test(m[1])` appended to safeHref's allowlist -- a
  // mutation that leaves intact the exact literal render_test.sh greps for, so
  // the shell suite cannot see it by construction -- a live data:text/html
  // anchor sat in #content and the old assertion reported ['example.com'] and
  // PASSED. This fixture now carries a data: and a vbscript: link so the
  // mutation has an input to be seen through.
  chk('beacon: every surviving anchor is a local path or the one allowed https host',
      r.anchors.map(a => a.scheme + '|' + a.host).sort(),
      ['file|', 'file|', 'https|example.com']);
  const hrefs = r.anchors.map(a => a.href);
  // Named for the one half it tests. The label used to promise the UNC half
  // too and never went near it; that property belongs to the scheme/host
  // assertion above, which grows a host the moment a `//host` spelling lives.
  chk('beacon: the javascript href is demoted', hrefs.includes('javascript:window.__PWN=1'), false);
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

// 7. The two defects a real browser walk found in template.html. Neither was
// visible to the shell suite, to this harness as it stood, or to jsdom -- one
// is a layout measurement and the other is which of two same-named elements a
// url(#) reference resolves to, and nothing that does not lay the page out can
// see either. Both were fixed with no assertion holding them, which is the only
// reason this block exists.
{
  // plan-region.md already carries a sequenceDiagram with autonumber, which is
  // what reaches arrowhead and sequencenumber -- the two markers the walk
  // watched vanish. Paired with plan.md so the page also holds the generated
  // flowchart, whose edge-path ids duplicate too: measured with nsIds() gone,
  // the pair reports 9 duplicated ids against the sequence fence's 7 alone.
  const f = render(join(FIX, 'plan-region.md'), join(FIX, 'plan.md'), join(W, 'themes.html'));
  const r = await probe(f);
  chk('themes: no id is shared between the light and the dark render',
      { duplicated: r.dupIds, markersOnPage: r.markerIds },
      { duplicated: [], markersOnPage: 8 });

  // Written into W, not added to tests/fixtures/: Task 16 pins fixture contents
  // by assertion, and a new fixture would drag that whole block along for a file
  // one assertion reads. It has to be its own page because no fixture holds an
  // unbreakable token: measured, the widest unbreakable run in any fixture's
  // prose lays out at 82px against a 480px viewport, so on any of them the
  // assertion below passes with the .doc rule deleted. The two literals here
  // are the ones the walk traced its 587px document width to, verbatim.
  // The table and the fenced block are here for the other half of the same rule:
  // both are allowed to scroll inside their own box, and neither may move the
  // body while doing it.
  const md = join(W, 'narrow.md');
  writeFileSync(md, [
    '# Narrow Viewport Probe',
    '',
    '## Why this change',
    '',
    'The cache path `~/.claude/plugins/cache/umbrella/umbrella/<version>/skills/<name>/SKILL.md`',
    'and the secure list `["secure","securityLevel","startOnLoad","maxTextSize","maxEdges"]`',
    'are the two literals the walk traced a 587px document width to at 480px.',
    '',
    '## Design',
    '',
    '| Setting | Value |',
    '| --- | --- |',
    '| secure | `["secure","securityLevel","startOnLoad","maxTextSize","maxEdges","htmlLabels"]` |',
    '',
    '```text',
    'a fenced line far wider than any 480px viewport, which has to scroll inside its own pre and never move the page body',
    '```',
    ''
  ].join('\n'));
  const nf = render(md, null, join(W, 'narrow.html'));
  const n = await narrow(nf, 480);
  chk('narrow: an unbreakable token in prose never scrolls the body at 480px',
      { overflowedAt: n.overflows, tokenWiderThanViewport: n.tokenWiderThanViewport },
      { overflowedAt: [], tokenWiderThanViewport: true });
}

// 8. mermaid `click ... href` -- the one route to an anchor that never passes
// the markdown renderer, and the one the shell suite structurally cannot reach.
// Measured against template.html before sweepLinks existed, on real render.sh
// output: securityLevel:"strict" stripped javascript: and `click ... call`, and
// passed `//host`, `/\host` and `\\host\share` through verbatim into an
// <a xlink:href> in BOTH theme renders -- six live remote anchors on one page.
// Clicking one in the dark render took location.href off the brief; on Windows
// that target is an SMB authentication attempt to a host of the payload's
// choosing. Load-time inertness was never involved, which is why every other
// probe on this page reads clean while it is wide open.
//
// Written into W rather than added to tests/fixtures/, for the reason block 7
// gives and one more: Task 16 pins beacon.md's payload-host line count at
// three, and every click directive here would add a fourth.
{
  const md = join(W, 'click.md');
  writeFileSync(md, [
    '# Mermaid Click Probe',
    '',
    '## Why this change',
    '',
    'One fence, nothing else that emits an anchor, so the anchors read below are',
    'this fence\'s and no other\'s. Node D is the allowlisted control: a sweep that',
    'demoted everything would satisfy an all-absent check just as well as a',
    'correct one, and D is what tells those two apart.',
    '',
    '```mermaid',
    'flowchart LR',
    '  A[pr] --> B[bs]',
    '  B --> C[unc]',
    '  C --> D[ok]',
    '  D --> E[js]',
    '  E --> F[call]',
    '  click A href "//evil.example.invalid/share"',
    '  click B href "/\\evil.example.invalid/share"',
    '  click C href "\\\\evil.example.invalid\\share"',
    '  click D href "https://example.com/"',
    '  click E href "javascript:window.__PWN=1"',
    '  click F call pwnFn()',
    '```',
    ''
  ].join('\n'));
  const f = render(md, null, join(W, 'click.html'));
  const r = await probe(f);
  const svg = r.anchors.filter(a => a.svg);
  const perSlot = s => svg.filter(a => a.slot === s).map(a => a.href);

  // The exact per-slot list, because no weaker form says all of it at once. A
  // count passes with the wrong five; an all-absent check passes on a page with
  // no SVG anchors at all, which is precisely what the old collector reported;
  // and a single page-wide list passes with the dark render left live. Five
  // entries per slot: A, B and C demoted by template.html, D allowed through,
  // E stripped by mermaid's own strict mode, and F's `call` form never becomes
  // an anchor at all -- so this also pins the two mermaid guarantees relied on.
  const HREFS = [null, null, null, 'https://example.com/', null];
  chk('click: both theme renders were swept, and only the allowed target survives',
      [perSlot('light'), perSlot('dark')], [HREFS, HREFS]);

  // The positive half, and the one that says the demotion MATCHES the markdown
  // path rather than merely happening: a rejected markdown link renders as
  // `text (href)`, so a rejected diagram target says the same thing from an SVG
  // <title>. All three hostile spellings, in document order, in both renders.
  const TITLES = [
    'pr (//evil.example.invalid/share)',
    'bs (/\\evil.example.invalid/share)',
    'unc (\\\\evil.example.invalid\\share)'
  ];
  chk('click: a rejected diagram target is demoted the way a rejected link is',
      ['light', 'dark'].map(s2 => svg.filter(a => a.slot === s2 && a.demoted !== null).map(a => a.demoted)),
      [TITLES, TITLES]);

  chk('click: no offsite requests', r.offsite, []);
  chk('click: no page errors', r.pageerrors, []);
}

await browser.close();
// Last, on the only path that reaches the summary: a block that threw never
// arrives here at all, which is louder still.
if (pass + fail !== EXPECTED) {
  no(`assertion inventory: ran ${pass + fail}`, `expected ${EXPECTED}`);
}
console.log(`\nbrowser: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
