import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_TWIN_DIST;
if (!directory) throw new Error("LEANRX_TWIN_DIST is required");

const files = new Set([
  "TwinLab.mjs",
  "leanrx_dom.mjs",
  "leanrx_region.mjs",
]);
let server;
let origin;

test.beforeAll(async () => {
  server = createServer(async (request, response) => {
    try {
      const requested = new URL(request.url, "http://localhost").pathname.slice(1);
      if (requested === "") {
        response.setHeader("content-type", "text/html; charset=utf-8");
        response.end("<!doctype html><html lang=\"en\"><head><title>Twin Lab</title></head><body><div id=\"app\"></div></body></html>");
      } else if (files.has(requested)) {
        response.setHeader("content-type", "text/javascript");
        response.end(await readFile(path.join(directory, requested)));
      } else {
        response.statusCode = 404;
        response.end("not found");
      }
    } catch (error) {
      response.statusCode = 500;
      response.end(String(error));
    }
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  origin = `http://127.0.0.1:${server.address().port}`;
});

test.afterAll(async () => {
  await new Promise((resolve, reject) =>
    server.close((error) => (error ? reject(error) : resolve())),
  );
});

async function mountTwin(page) {
  await page.goto(origin);
  await page.evaluate(async () => {
    const { mount } = await import("/TwinLab.mjs");
    globalThis.twinDispose = mount(document.getElementById("app"));
  });
}

// Seeds one `flag == "true"` row and one `flag == "false"` row into every
// region, so each of the three filter tables has a hit and a miss to select
// between.
async function seedBoth(page, displayed = [2, 2, 2]) {
  await page.getByRole("button", { name: "Seed on" }).click();
  await page.getByRole("button", { name: "Seed off" }).click();
  // The counts are of *displayed* rows: since ADR-0102 a deselected row is
  // not in its container, so a seed under an active filter shows fewer.
  await expect(page.locator("#left > li")).toHaveCount(displayed[0]);
  await expect(page.locator("#right > li")).toHaveCount(displayed[1]);
  await expect(page.locator("#solo > li")).toHaveCount(displayed[2]);
}

// The trace slice has to be measured from inside the page: the mark is stashed
// on `globalThis` *before* the click so the post-click read can slice from it.
async function markTrace(page) {
  return page.evaluate(() => {
    const tx = globalThis.twinDispose.instrumentation();
    globalThis.twinTraceLength = tx[7].length;
    return {
      commits: tx[1],
      counts: tx[5],
      evaluations: tx[8],
      writes: tx[9],
      metrics: globalThis.twinDispose.regionInstrumentation(),
    };
  });
}

async function readTrace(page) {
  return page.evaluate(() => {
    const tx = globalThis.twinDispose.instrumentation();
    return {
      commits: tx[1],
      counts: tx[5],
      evaluations: tx[8],
      writes: tx[9],
      slice: tx[7].slice(globalThis.twinTraceLength),
      metrics: globalThis.twinDispose.regionInstrumentation(),
    };
  });
}

function occurrences(slice, event) {
  return slice.filter((entry) => entry === event).length;
}

// ADR-0086: one entry per sweep carrying how many rows it wrote, so the
// per-row cache is observable without a host counter and without an entry per
// row. One number per sweep the window saw, in commit order.
function writtenCounts(slice, region) {
  const prefix = `filter:${region}:written:`;
  return slice
    .filter((entry) => entry.startsWith(prefix))
    .map((entry) => Number(entry.slice(prefix.length)));
}

// ADR-0080: `mode` is routed, so a `mode` button writes the canonical hash
// inside its own commit and the browser answers with one `hashchange` whose
// dispatch is an equal-value set-field commit (ADR-0063) — a second commit
// that wakes no sweep. `flipMode` returns once both have landed, so a trace
// window opened afterwards measures only what follows it.
async function flipMode(page, name, hash) {
  const before = await page.evaluate(
    () => globalThis.twinDispose.instrumentation()[1],
  );
  await page.getByRole("button", { name }).click();
  await expect(page).toHaveURL(new RegExp(`${hash}$`));
  await expect
    .poll(() => page.evaluate(() => globalThis.twinDispose.instrumentation()[1]))
    .toBe(before + 2);
}

test("one transaction appends into three regions and mounts three rows (ADR-0098)", async ({ page }) => {
  await mountTwin(page);
  await seedBoth(page);
  await page.evaluate(() => {
    globalThis.standing = ["left", "right", "solo"].map((name) =>
      [...document.querySelectorAll(`#${name} > li`)]);
  });
  const before = await markTrace(page);
  // `seedOn` is `append left (…) then append right (…) then append solo (…)`:
  // three regions, one row each, inside one transaction. Each region carries
  // its own counter and its own drain, so the commit mounts three rows and
  // re-renders none of the six standing ones.
  await page.getByRole("button", { name: "Seed on" }).click();
  await expect(page.locator("#left > li")).toHaveCount(3);
  await expect(page.locator("#right > li")).toHaveCount(3);
  await expect(page.locator("#solo > li")).toHaveCount(3);
  const after = await readTrace(page);
  expect(after.commits).toBe(before.commits + 1);
  for (const index of [0, 1, 2]) {
    expect(after.metrics[index][0]).toBe(before.metrics[index][0] + 1);
    expect(after.metrics[index][1]).toBe(before.metrics[index][1]);
    expect(after.metrics[index][3]).toBe(before.metrics[index][3]);
  }
  for (const name of ["left", "right", "solo"]) {
    expect(occurrences(after.slice, `region:${name}:insertAt`)).toBe(1);
    expect(occurrences(after.slice, `region:${name}:update`)).toBe(0);
  }
  // Every standing row in every region keeps the exact DOM node it had.
  const retained = await page.evaluate(() =>
    ["left", "right", "solo"].every((name, region) => {
      const rows = document.querySelectorAll(`#${name} > li`);
      return globalThis.standing[region].every((node, index) => node === rows[index]);
    }));
  expect(retained).toBe(true);
});

test("three filtered regions mount with their own containers", async ({ page }) => {
  await mountTwin(page);
  await expect(page.locator("#left-line")).toHaveText("0 left, 0 on");
  await seedBoth(page);
  await expect(page.locator("#left-line")).toHaveText("2 left, 1 on");
  await expect(page.locator("#left .twin-label")).toHaveText(["L0", "L1"]);
  await expect(page.locator("#right .twin-label")).toHaveText(["R0", "R1"]);
  await expect(page.locator("#solo .twin-label")).toHaveText(["S0", "S1"]);
  // Every row starts displayed: `all` is outside all three tables.
  await expect(page.locator("#left > li").first()).toBeVisible();
  await expect(page.locator("#right > li").first()).toBeVisible();
  await expect(page.locator("#solo > li").first()).toBeVisible();
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("one state field drives both twin sweeps in one commit", async ({ page }) => {
  await mountTwin(page);
  await seedBoth(page);
  const before = await markTrace(page);
  // ADR-0079: `mode` carries both twins' filters, so one `set mode "on"`
  // raises one changed bit that wakes two sweeps. The arm tables are
  // inverted, so the same field value hides complementary rows.
  await page.getByRole("button", { name: "Show on" }).click();
  // ADR-0102: a deselected row leaves its own container, so each region's
  // children *are* its own selection — three containers, three selections.
  await expect(page.locator("#left .twin-label")).toHaveText(["L0"]);
  await expect(page.locator("#right .twin-label")).toHaveText(["R1"]);
  // `solo` reads `tone`, still `"all"`: it is not woken at all.
  await expect(page.locator("#solo .twin-label")).toHaveText(["S0", "S1"]);
  // ADR-0080: the flip writes the canonical hash, so the browser answers with
  // one `hashchange` — an equal-value set-field commit. The window below is
  // widened over *both* commits to show that the echo wakes neither sweep.
  await expect(page).toHaveURL(/#\/on$/);
  await expect
    .poll(() => page.evaluate(() => globalThis.twinDispose.instrumentation()[1]))
    .toBe(before.commits + 2);
  const after = await readTrace(page);
  expect(after.commits).toBe(before.commits + 2);
  expect(occurrences(after.slice, "transaction:commit")).toBe(2);
  // Only the first commit does any work: one changed bit, two sweeps, once
  // each — and one route write for the two regions that share the field.
  expect(occurrences(after.slice, "route:mode:write")).toBe(1);
  expect(occurrences(after.slice, "filter:left:evaluated")).toBe(1);
  expect(occurrences(after.slice, "filter:right:evaluated")).toBe(1);
  expect(occurrences(after.slice, "filter:solo:evaluated")).toBe(0);
  // Region declaration order, not event order or first-touched order.
  expect(after.slice.indexOf("filter:left:evaluated"))
    .toBeLessThan(after.slice.indexOf("filter:right:evaluated"));
  // Two sweeps, two evaluate ticks — no third scan hiding behind the pair.
  expect(after.evaluations).toBe(before.evaluations + 2);
  // A filter flip mounts and disposes nothing in any region.
  expect(after.metrics).toEqual(before.metrics);
});

test("a second field filters the third region alone", async ({ page }) => {
  await mountTwin(page);
  await seedBoth(page);
  await flipMode(page, "Show on", "#/on");
  const before = await page.evaluate(() => {
    const tx = globalThis.twinDispose.instrumentation();
    globalThis.twinTraceLength = tx[7].length;
    globalThis.twinRows = Array.from(document.querySelectorAll("#left > li, #right > li"));
    return {
      commits: tx[1],
      counts: tx[5],
      evaluations: tx[8],
      metrics: globalThis.twinDispose.regionInstrumentation(),
      displayed: globalThis.twinRows.map((row) => row.isConnected),
    };
  });
  // ADR-0079: `tone` drives only `solo`'s sweep. The twins keep the selection
  // their own field left them with, and neither is re-evaluated.
  await page.getByRole("button", { name: "Tone on" }).click();
  await expect(page.locator("#solo .twin-label")).toHaveText(["S0"]);
  const after = await page.evaluate(() => {
    const tx = globalThis.twinDispose.instrumentation();
    return {
      commits: tx[1],
      evaluations: tx[8],
      slice: tx[7].slice(globalThis.twinTraceLength),
      metrics: globalThis.twinDispose.regionInstrumentation(),
      displayed: globalThis.twinRows.map((row) => row.isConnected),
    };
  });
  expect(after.commits).toBe(before.commits + 1);
  expect(occurrences(after.slice, "filter:solo:evaluated")).toBe(1);
  expect(occurrences(after.slice, "filter:left:evaluated")).toBe(0);
  expect(occurrences(after.slice, "filter:right:evaluated")).toBe(0);
  expect(after.evaluations).toBe(before.evaluations + 1);
  expect(after.displayed).toEqual(before.displayed);
  expect(after.metrics).toEqual(before.metrics);
  // The unfiltered-by-`tone` twins keep their row count too.
  await expect(page.locator("#left-line")).toHaveText("2 left, 1 on");
});

test("a region touch alone wakes only that region's sweep", async ({ page }) => {
  await mountTwin(page);
  await seedBoth(page);
  await flipMode(page, "Show on", "#/on");
  const before = await markTrace(page);
  // No field changes: `left`'s sweep wakes on its own touched flag, and the
  // twin sharing its filter field stays asleep.
  await page.getByRole("button", { name: "Add left" }).click();
  // The appended row carries `flag == "true"`, so the `on` selection takes
  // it and the deselected L1 is still out (ADR-0102).
  await expect(page.locator("#left .twin-label")).toHaveText(["L0", "L2"]);
  const after = await readTrace(page);
  expect(occurrences(after.slice, "filter:left:evaluated")).toBe(1);
  expect(occurrences(after.slice, "filter:right:evaluated")).toBe(0);
  expect(occurrences(after.slice, "filter:solo:evaluated")).toBe(0);
  expect(after.evaluations).toBe(before.evaluations + 1);
  // A removal is the same story from the other side.
  const beforeRemoval = await markTrace(page);
  await page.locator("#left > li").first()
    .getByRole("button", { name: "Remove left" }).click();
  await expect(page.locator("#left .twin-label")).toHaveText(["L2"]);
  const afterRemoval = await readTrace(page);
  expect(occurrences(afterRemoval.slice, "filter:left:evaluated")).toBe(1);
  expect(occurrences(afterRemoval.slice, "filter:right:evaluated")).toBe(0);
  expect(occurrences(afterRemoval.slice, "filter:solo:evaluated")).toBe(0);
  expect(afterRemoval.evaluations).toBe(beforeRemoval.evaluations + 1);
  // The table behind the selection is what the removal actually touched:
  // clearing the filter shows the two survivors in table order.
  await flipMode(page, "Show all", "#/");
  await expect(page.locator("#left .twin-label")).toHaveText(["L1", "L2"]);
});

test("one transaction mixes a region touch with a shared filter change", async ({ page }) => {
  await mountTwin(page);
  await seedBoth(page);
  const before = await markTrace(page);
  // ADR-0079: `stir` appends to `solo` and writes `mode` in one transaction,
  // so the commit sweep wakes `solo` by its touched flag and the twins by the
  // changed bit — three sweeps, one commit, declaration order, once each.
  await page.getByRole("button", { name: "Stir" }).click();
  await expect(page.locator("#solo .twin-label")).toHaveText(["S0", "S1", "S2"]);
  await expect(page.locator("#left .twin-label")).toHaveText(["L0"]);
  await expect(page.locator("#right .twin-label")).toHaveText(["R1"]);
  // `tone` is untouched, so `solo`'s own table still shows every row —
  // which is why its three labels above are all three of them.
  // `stir` writes `mode`, so its commit writes the hash and the echo follows
  // — one more commit that wakes none of the three sweeps.
  await expect(page).toHaveURL(/#\/on$/);
  await expect
    .poll(() => page.evaluate(() => globalThis.twinDispose.instrumentation()[1]))
    .toBe(before.commits + 2);
  const after = await readTrace(page);
  expect(after.commits).toBe(before.commits + 2);
  expect(occurrences(after.slice, "transaction:commit")).toBe(2);
  expect(occurrences(after.slice, "route:mode:write")).toBe(1);
  expect(occurrences(after.slice, "filter:left:evaluated")).toBe(1);
  expect(occurrences(after.slice, "filter:right:evaluated")).toBe(1);
  expect(occurrences(after.slice, "filter:solo:evaluated")).toBe(1);
  expect(after.evaluations).toBe(before.evaluations + 3);
  // The append lands first — event order — and the three sweeps then run in
  // region declaration order regardless of which region the event touched.
  expect(after.slice.indexOf("region:solo:append"))
    .toBeLessThan(after.slice.indexOf("source:mode:write"));
  expect(after.slice.indexOf("source:mode:write"))
    .toBeLessThan(after.slice.indexOf("filter:left:evaluated"));
  expect(after.slice.indexOf("filter:left:evaluated"))
    .toBeLessThan(after.slice.indexOf("filter:right:evaluated"));
  expect(after.slice.indexOf("filter:right:evaluated"))
    .toBeLessThan(after.slice.indexOf("filter:solo:evaluated"));
  // The touched region reconciles before its own sweep; the untouched twins
  // never reconcile at all.
  expect(after.slice.indexOf("region:solo:update"))
    .toBeLessThan(after.slice.indexOf("filter:solo:evaluated"));
  expect(occurrences(after.slice, "region:left:update")).toBe(0);
  expect(occurrences(after.slice, "region:right:update")).toBe(0);
});

test("a union literal only one twin declares seeds from the hash", async ({ page }) => {
  await page.goto(origin);
  await page.evaluate(async () => {
    location.hash = "#/mixed";
    const { mount } = await import("/TwinLab.mjs");
    globalThis.twinDispose = mount(document.getElementById("app"));
  });
  await seedBoth(page, [2, 1, 2]);
  // ADR-0080: `"mixed"` is named by `right`'s arm table alone. The route's
  // sealed literal set is the declared default plus the *union* of every
  // filter table over `mode`, so `#/mixed` is a legal hash on the strength of
  // the second-declared table — under a first-match rule it would have been
  // rejected purely because `left` is declared first. At runtime the region
  // that names the literal filters, and the twin that does not falls through
  // to show-all, which is exactly what its own arm chain already does.
  await expect(page.locator("#right .twin-label")).toHaveText(["R0"]);
  await expect(page.locator("#left .twin-label")).toHaveText(["L0", "L1"]);
  // `solo` reads `tone`; the routed field never reaches it.
  await expect(page.locator("#solo .twin-label")).toHaveText(["S0", "S1"]);
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("one hashchange wakes both twin sweeps and writes the hash once", async ({ page }) => {
  await mountTwin(page);
  await seedBoth(page);
  const before = await markTrace(page);
  // ADR-0080: the hash dispatch is the ordinary set-field transaction, so one
  // `hashchange` raises the one `changed[mode]` bit that both twin sweeps are
  // guarded on — two sweeps, one commit, still in declaration order.
  await page.evaluate(() => {
    location.hash = "#/off";
  });
  await expect(page.locator("#left .twin-label")).toHaveText(["L1"]);
  await expect(page.locator("#right .twin-label")).toHaveText(["R0"]);
  const after = await readTrace(page);
  expect(after.commits).toBe(before.commits + 1);
  expect(after.slice).toContain("event:route:mode:off");
  expect(occurrences(after.slice, "filter:left:evaluated")).toBe(1);
  expect(occurrences(after.slice, "filter:right:evaluated")).toBe(1);
  expect(occurrences(after.slice, "filter:solo:evaluated")).toBe(0);
  expect(after.slice.indexOf("filter:left:evaluated"))
    .toBeLessThan(after.slice.indexOf("filter:right:evaluated"));
  expect(after.evaluations).toBe(before.evaluations + 2);
  // One route write for the two regions that share the field — the write
  // rides the routed field's changed bit, not any region's touched flag —
  // and it is equal-value here, so no echo commit follows.
  expect(occurrences(after.slice, "route:mode:write")).toBe(1);
  expect(occurrences(after.slice, "transaction:commit")).toBe(1);
  expect(after.metrics).toEqual(before.metrics);
  // The same hash dispatch reaches the union literal too.
  const beforeMixed = await markTrace(page);
  await page.evaluate(() => {
    location.hash = "#/mixed";
  });
  await expect(page.locator("#left .twin-label")).toHaveText(["L0", "L1"]);
  await expect(page.locator("#right .twin-label")).toHaveText(["R0"]);
  const afterMixed = await readTrace(page);
  expect(afterMixed.commits).toBe(beforeMixed.commits + 1);
  expect(afterMixed.slice).toContain("event:route:mode:mixed");
  expect(occurrences(afterMixed.slice, "filter:left:evaluated")).toBe(1);
  expect(occurrences(afterMixed.slice, "filter:right:evaluated")).toBe(1);
  expect(occurrences(afterMixed.slice, "filter:solo:evaluated")).toBe(0);
  expect(afterMixed.metrics).toEqual(beforeMixed.metrics);
});

test("a row update drains beside the filter sweep at region index 1", async ({ page }) => {
  await mountTwin(page);
  await seedBoth(page);
  await flipMode(page, "Show on", "#/on");
  // Under `"on"` `right` keeps the `flag == "false"` rows, so R1 alone is in
  // the container (ADR-0102) and is the container's only child.
  await expect(page.locator("#right .twin-label")).toHaveText(["R1"]);
  const before = await page.evaluate(() => {
    const tx = globalThis.twinDispose.instrumentation();
    globalThis.twinTraceLength = tx[7].length;
    globalThis.twinRow = document.querySelectorAll("#right > li")[0];
    return {
      commits: tx[1],
      evaluations: tx[8],
      metrics: globalThis.twinDispose.regionInstrumentation(),
    };
  });
  // ADR-0080: the checkbox writes the very field `right`'s filter reads, so
  // one commit drains the pending row through `updateAt` and then re-selects
  // it — a drain beside a filter sweep at region index *1*, where the two had
  // never met (Toggle Lab and Mix Lab only ever pair them at index 0).
  await page.locator("#right > li").nth(0)
    .getByRole("checkbox", { name: "Flag right" }).click();
  await expect(page.locator("#right > li")).toHaveCount(0);
  const after = await readTrace(page);
  const flag = await page.evaluate(
    () => globalThis.twinRow.querySelector(".twin-flag").textContent,
  );
  expect(flag).toBe("true");
  expect(after.commits).toBe(before.commits + 1);
  // The drain runs first; the sweep then reads the settled row table. The
  // pending array feeds `region_touched_1`, so one flag wakes both.
  expect(occurrences(after.slice, "region:right:updateAt")).toBe(1);
  expect(occurrences(after.slice, "region:right:update")).toBe(0);
  expect(occurrences(after.slice, "filter:right:evaluated")).toBe(1);
  expect(after.slice.indexOf("region:right:updateAt"))
    .toBeLessThan(after.slice.indexOf("filter:right:evaluated"));
  // The twin sharing the filter field stays asleep: no field changed, and
  // `left` was never touched.
  expect(occurrences(after.slice, "filter:left:evaluated")).toBe(0);
  expect(occurrences(after.slice, "filter:solo:evaluated")).toBe(0);
  expect(after.evaluations).toBe(before.evaluations + 1);
  // One update in `right` — no mount, no move, no disposal anywhere — and
  // the drained row is the same node it was.
  expect(after.metrics[1]).toEqual([
    before.metrics[1][0], before.metrics[1][1] + 1,
    before.metrics[1][2], before.metrics[1][3],
  ]);
  expect(after.metrics[0]).toEqual(before.metrics[0]);
  expect(after.metrics[2]).toEqual(before.metrics[2]);
  // The drained row is out of the container, still the region's, and comes
  // back the same node when the filter selects it again.
  expect(await page.evaluate(() => globalThis.twinRow.isConnected)).toBe(false);
  await flipMode(page, "Show off", "#/off");
  const identical = await page.evaluate(
    () => document.querySelectorAll("#right > li")[1] === globalThis.twinRow,
  );
  expect(identical).toBe(true);
  // The ADR-0060 checked reflection survives the drain: the box the click
  // set stays set after the row is re-rendered and re-selected.
  const checked = await page.evaluate(
    () => globalThis.twinRow.querySelector("input").checked,
  );
  expect(checked).toBe(true);
});

test("a row write outside the filter subject drains without waking the sweep",
  async ({ page }) => {
  await mountTwin(page);
  await seedBoth(page);
  // Held while every row is still in the container, because the flip below
  // takes one of them out of it (ADR-0102) and out of every locator with it.
  await page.evaluate(() => {
    globalThis.twinAll = Array.from(document.querySelectorAll("#left > li"));
  });
  await flipMode(page, "Show on", "#/on");
  // Under `"on"` `left` keeps the `flag == "true"` rows, so L0 is in the
  // container and L1 is out of it. `mark` writes `label`, which no arm of
  // `left`'s table reads.
  await expect(page.locator("#left .twin-label")).toHaveText(["L0"]);
  const before = await page.evaluate(() => {
    const tx = globalThis.twinDispose.instrumentation();
    globalThis.twinTraceLength = tx[7].length;
    globalThis.twinRows = Array.from(document.querySelectorAll("#left > li"));
    return {
      commits: tx[1],
      counts: tx[5],
      evaluations: tx[8],
      metrics: globalThis.twinDispose.regionInstrumentation(),
      displayed: globalThis.twinRows.map((row) => row.isConnected),
    };
  });
  // ADR-0082: the drain queues a position, so the region *is* touched — but
  // the sweep is guarded on the structural bit alone, because no drain path
  // of this region writes a field its arms read. One `updateAt`, no scan.
  await page.locator("#left > li").nth(0)
    .getByRole("button", { name: "Mark left" }).click();
  await expect(page.locator("#left .twin-label").nth(0)).toHaveText("L0*");
  const after = await readTrace(page);
  expect(after.commits).toBe(before.commits + 1);
  expect(occurrences(after.slice, "region:left:updateAt")).toBe(1);
  expect(occurrences(after.slice, "region:left:update")).toBe(0);
  expect(occurrences(after.slice, "filter:left:evaluated")).toBe(0);
  expect(occurrences(after.slice, "dom:filter:left:write")).toBe(0);
  expect(after.evaluations).toBe(before.evaluations);
  // ADR-0083 closes the sibling axis: the count sweep beside it is derived
  // from its own read set, and neither count reads `label`. The row total
  // reads only `rows.length`, which a drain cannot move; the predicate count
  // reads `flag`, which this region's only drain path does not write. So the
  // drain asks neither — the O(N) predicate scan does not run at all, and
  // tx[5] is where that shows.
  expect(occurrences(after.slice, "count:left:0:evaluated")).toBe(0);
  expect(occurrences(after.slice, "count:left:1:evaluated")).toBe(0);
  expect(occurrences(after.slice, "dom:count:left:0:write")).toBe(0);
  expect(after.counts).toBe(before.counts);
  // The counts on screen are still the ones the last structural commit left.
  await expect(page.locator("#left-line")).toHaveText("2 left, 1 on");
  // The selection is exactly where the last sweep left it, on the row the
  // drain touched: still displayed, still the same node.
  const marked = await page.evaluate(() => ({
    displayed: globalThis.twinRows.map((row) => row.isConnected),
    identical: globalThis.twinRows.every((row) => document.contains(row)),
  }));
  expect(marked.displayed).toEqual(before.displayed);
  expect(marked.identical).toBe(true);
  // ADR-0102 closes the other half of this case rather than answering it: a
  // deselected row is not in the container, and the delegated listener is,
  // so nothing can drain a row the filter is not showing. The same
  // programmatic click that used to reach the hidden L1 now reaches a node
  // outside the document and moves nothing at all.
  const beforeHidden = await markTrace(page);
  expect(await page.evaluate(() =>
    globalThis.twinAll.map((row) => row.isConnected))).toEqual([true, false]);
  await page.evaluate(() => {
    globalThis.twinAll[1].querySelector(".twin-marks button").click();
  });
  await page.waitForTimeout(50);
  const afterHidden = await readTrace(page);
  expect(afterHidden.commits).toBe(beforeHidden.commits);
  expect(occurrences(afterHidden.slice, "region:left:updateAt")).toBe(0);
  expect(occurrences(afterHidden.slice, "filter:left:evaluated")).toBe(0);
  expect(afterHidden.evaluations).toBe(beforeHidden.evaluations);
  expect(afterHidden.counts).toBe(beforeHidden.counts);
  // The twins' shared field and the unrelated region are untouched, and a
  // structural touch afterwards still wakes the sweep and re-selects every
  // row — the marked label included.
  expect(occurrences(afterHidden.slice, "filter:right:evaluated")).toBe(0);
  expect(occurrences(afterHidden.slice, "filter:solo:evaluated")).toBe(0);
  const beforeAppend = await markTrace(page);
  await page.getByRole("button", { name: "Add left" }).click();
  await expect(page.locator("#left .twin-label")).toHaveText(["L0*", "L2"]);
  const afterAppend = await readTrace(page);
  expect(occurrences(afterAppend.slice, "filter:left:evaluated")).toBe(1);
  expect(afterAppend.evaluations).toBe(beforeAppend.evaluations + 1);
  // The structural touch wakes both counts in the one block they share, and
  // the appended row is a `flag == "true"` one, so both texts move.
  expect(afterAppend.counts).toBe(beforeAppend.counts + 2);
  await expect(page.locator("#left-line")).toHaveText("3 left, 2 on");
  // The whole table, with the deselected row back at its own position.
  await flipMode(page, "Show all", "#/");
  await expect(page.locator("#left .twin-label")).toHaveText(["L0*", "L1", "L2"]);
});

test("flipping back restores every region without remounting a row", async ({ page }) => {
  await mountTwin(page);
  await seedBoth(page);
  await flipMode(page, "Show on", "#/on");
  await page.getByRole("button", { name: "Tone on" }).click();
  const before = await page.evaluate(() => {
    globalThis.twinRows = Array.from(document.querySelectorAll("li"));
    return globalThis.twinDispose.regionInstrumentation();
  });
  await flipMode(page, "Show off", "#/off");
  await expect(page.locator("#left .twin-label")).toHaveText(["L1"]);
  await expect(page.locator("#right .twin-label")).toHaveText(["R0"]);
  await flipMode(page, "Show all", "#/");
  await page.getByRole("button", { name: "Tone all" }).click();
  // Every row is back, each at its own table position — the rows the two
  // flips took out are re-inserted, not remounted, and none of them arrived
  // at an end (ADR-0102).
  await expect(page.locator("#left .twin-label")).toHaveText(["L0", "L1"]);
  await expect(page.locator("#right .twin-label")).toHaveText(["R0", "R1"]);
  await expect(page.locator("#solo .twin-label")).toHaveText(["S0", "S1"]);
  const after = await page.evaluate(() => ({
    metrics: globalThis.twinDispose.regionInstrumentation(),
    identical: globalThis.twinRows.every((row) => document.contains(row)),
    rows: document.querySelectorAll("li").length,
  }));
  expect(after.metrics).toEqual(before);
  expect(after.identical).toBe(true);
  expect(after.rows).toBe(6);
});

test("a route flip persists nothing and a row touch writes no hash", async ({ page }) => {
  await mountTwin(page);
  await seedBoth(page);
  // `right` is the persisted region, so the two seed events have already
  // written it once each; `left` and `solo` own no key at all.
  const seeded = await page.evaluate(() => ({
    right: localStorage.getItem("leanrx-twin-lab.right"),
    left: localStorage.getItem("leanrx-twin-lab.left"),
    solo: localStorage.getItem("leanrx-twin-lab.solo"),
  }));
  expect(seeded.right).toBe("R0,true;R1,false");
  expect(seeded.left).toBeNull();
  expect(seeded.solo).toBeNull();
  const before = await markTrace(page);
  // ADR-0081: the routed field drives two regions and *one* of them persists.
  // The persistence sweep is guarded on `region_touched_1` alone, so a flip
  // of the field both twins filter on cannot reach it — two sweeps run, the
  // hash is rewritten, and the stored string is untouched.
  await page.getByRole("button", { name: "Show on" }).click();
  await expect(page.locator("#right .twin-label")).toHaveText(["R1"]);
  await expect(page).toHaveURL(/#\/on$/);
  await expect
    .poll(() => page.evaluate(() => globalThis.twinDispose.instrumentation()[1]))
    .toBe(before.commits + 2);
  const flipped = await readTrace(page);
  expect(occurrences(flipped.slice, "route:mode:write")).toBe(1);
  expect(occurrences(flipped.slice, "filter:left:evaluated")).toBe(1);
  expect(occurrences(flipped.slice, "filter:right:evaluated")).toBe(1);
  expect(occurrences(flipped.slice, "storage:right:write")).toBe(0);
  expect(await page.evaluate(
    () => localStorage.getItem("leanrx-twin-lab.right"),
  )).toBe("R0,true;R1,false");
  // The other direction: a row touch in the persisted region rides its own
  // touched flag into one storageSet and changes no state field, so the
  // route write block never opens and the URL stays where the flip left it.
  const beforeToggle = await markTrace(page);
  await page.locator("#right > li").nth(0)
    .getByRole("checkbox", { name: "Flag right" }).click();
  await expect(page.locator("#right > li")).toHaveCount(0);
  const toggled = await readTrace(page);
  expect(toggled.commits).toBe(beforeToggle.commits + 1);
  expect(occurrences(toggled.slice, "storage:right:write")).toBe(1);
  expect(occurrences(toggled.slice, "route:mode:write")).toBe(0);
  expect(occurrences(toggled.slice, "filter:right:evaluated")).toBe(1);
  expect(occurrences(toggled.slice, "filter:left:evaluated")).toBe(0);
  // The write-back carries the drained row, and rides the same touched flag
  // the drain and the sweep do — one commit, one serialization.
  expect(await page.evaluate(
    () => localStorage.getItem("leanrx-twin-lab.right"),
  )).toBe("R0,true;R1,true");
  await expect(page).toHaveURL(/#\/on$/);
});

test("a routed literal filters the rows its own hydration mounted", async ({ page }) => {
  await page.goto(origin);
  await page.evaluate(async () => {
    localStorage.setItem("leanrx-twin-lab.right", "R0,true;R1,false");
    location.hash = "#/mixed";
    const { mount } = await import("/TwinLab.mjs");
    globalThis.twinDispose = mount(document.getElementById("app"));
  });
  // ADR-0081: mount seeds `mode` from the hash before the DOM exists and runs
  // the hydrate transaction after the listeners are wired, so the hydrate
  // commit's own sweep applies the routed literal to the rows it just
  // mounted — no second commit, and no hash write, because the routed field
  // never changed inside that transaction.
  await expect(page.locator("#right .twin-label")).toHaveText(["R0"]);
  // Persistence is per region, exactly as filters and counts are: the two
  // unpersisted regions mount empty even though one of them shares the
  // routed field.
  await expect(page.locator("#left > li")).toHaveCount(0);
  await expect(page.locator("#solo > li")).toHaveCount(0);
  await expect(page).toHaveURL(/#\/mixed$/);
  const hydrated = await page.evaluate(() => ({
    commits: globalThis.twinDispose.instrumentation()[1],
    trace: globalThis.twinDispose.instrumentation()[7],
    stored: localStorage.getItem("leanrx-twin-lab.right"),
  }));
  expect(hydrated.commits).toBe(1);
  for (const event of [
    "event:hydrate:right", "region:right:hydrate",
    "filter:right:evaluated", "storage:right:write",
  ]) {
    expect(hydrated.trace).toContain(event);
  }
  expect(hydrated.trace).not.toContain("route:mode:write");
  expect(hydrated.trace.indexOf("region:right:hydrate"))
    .toBeLessThan(hydrated.trace.indexOf("filter:right:evaluated"));
  // `left` shares the routed field but owns no rows to sweep, and `solo`
  // reads a different field entirely.
  expect(hydrated.trace).not.toContain("storage:left:write");
  expect(hydrated.stored).toBe("R0,true;R1,false");
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("the filter sweep writes exactly the rows whose selection moved (ADR-0086)",
  async ({ page }) => {
  await mountTwin(page);
  // The first row of every region is born with an unwritten displayed-state
  // cell — `null` differs from both booleans — so each of the three sweeps
  // writes exactly the row it has just seen for the first time.
  const beforeFirst = await markTrace(page);
  await page.getByRole("button", { name: "Seed on" }).click();
  await expect(page.locator("#left > li")).toHaveCount(1);
  const afterFirst = await readTrace(page);
  expect(writtenCounts(afterFirst.slice, "left")).toEqual([1]);
  expect(writtenCounts(afterFirst.slice, "right")).toEqual([1]);
  expect(writtenCounts(afterFirst.slice, "solo")).toEqual([1]);
  expect(afterFirst.writes).toBe(beforeFirst.writes + 3);
  // A second append evaluates two rows per region and writes exactly the
  // appended one: the row that was already selected keeps its cell, and the
  // sweep never reaches its DOM node at all.
  const beforeSecond = await markTrace(page);
  await page.getByRole("button", { name: "Seed off" }).click();
  await expect(page.locator("#left > li")).toHaveCount(2);
  const afterSecond = await readTrace(page);
  expect(writtenCounts(afterSecond.slice, "left")).toEqual([1]);
  expect(writtenCounts(afterSecond.slice, "right")).toEqual([1]);
  expect(writtenCounts(afterSecond.slice, "solo")).toEqual([1]);
  expect(afterSecond.evaluations).toBe(beforeSecond.evaluations + 3);
  expect(afterSecond.writes).toBe(beforeSecond.writes + 3);
  // A filter *state* change is the asymmetry with ADR-0085's cell: the value
  // is a function of the row's fields *and* the filter field, so no write
  // site can pre-stale one row — every row is stale at once. The sweep
  // recomputes all of them and still writes only what moved: under `"on"`
  // `left` hides its `flag == "false"` row and `right`, whose table is
  // inverted, hides its `flag == "true"` one.
  const beforeFlip = await markTrace(page);
  await page.evaluate(() => {
    globalThis.twinLeft = Array.from(document.querySelectorAll("#left > li"));
  });
  await flipMode(page, "Show on", "#/on");
  await expect(page.locator("#left .twin-label")).toHaveText(["L0"]);
  const afterFlip = await readTrace(page);
  expect(writtenCounts(afterFlip.slice, "left")).toEqual([1]);
  expect(writtenCounts(afterFlip.slice, "right")).toEqual([1]);
  expect(writtenCounts(afterFlip.slice, "solo")).toEqual([]);
  expect(afterFlip.writes).toBe(beforeFlip.writes + 2);
  // The identity keying, measured: `remove` rebuilds the row array around
  // unchanged tuples and detaches one node, so every survivor's cell and its
  // untouched DOM node still agree. The sweep runs — the region is
  // structurally dirty — evaluates the survivor and writes *nothing*.
  const beforeRemove = await page.evaluate(() => {
    const tx = globalThis.twinDispose.instrumentation();
    globalThis.twinTraceLength = tx[7].length;
    globalThis.twinSurvivor = globalThis.twinLeft[1];
    return { writes: tx[9], evaluations: tx[8] };
  });
  await page.locator("#left > li").nth(0)
    .getByRole("button", { name: "Remove left" }).click();
  await expect(page.locator("#left > li")).toHaveCount(0);
  const afterRemove = await readTrace(page);
  expect(writtenCounts(afterRemove.slice, "left")).toEqual([0]);
  expect(occurrences(afterRemove.slice, "filter:left:evaluated")).toBe(1);
  expect(occurrences(afterRemove.slice, "dom:filter:left:write")).toBe(0);
  expect(afterRemove.evaluations).toBe(beforeRemove.evaluations + 1);
  expect(afterRemove.writes).toBe(beforeRemove.writes);
  // The survivor is out of the container and comes back as itself when the
  // filter selects it: a `remove` rebuilt the array around unchanged tuples,
  // so the cell and the detached node still agree and the sweep writes
  // nothing (ADR-0102 does not change that — it changes what a write is).
  expect(await page.evaluate(() => globalThis.twinSurvivor.isConnected)).toBe(false);
  await flipMode(page, "Show off", "#/off");
  expect(await page.evaluate(
    () => document.querySelectorAll("#left > li")[0] === globalThis.twinSurvivor,
  )).toBe(true);
  await flipMode(page, "Show on", "#/on");
  // A row event that writes the filter's own subject moves exactly its own
  // row, and the two per-row caches show up side by side in one commit: the
  // ADR-0085 cell re-encodes one row and this one rewrites one row's
  // `hidden`, while the other row pays neither.
  const beforeToggle = await markTrace(page);
  await page.locator("#right > li").nth(0)
    .getByRole("checkbox", { name: "Flag right" }).click();
  await expect(page.locator("#right > li")).toHaveCount(0);
  const afterToggle = await readTrace(page);
  expect(writtenCounts(afterToggle.slice, "right")).toEqual([1]);
  expect(afterToggle.slice).toContain("storage:right:encode:1");
  expect(afterToggle.writes).toBe(beforeToggle.writes + 1);
  expect(occurrences(afterToggle.slice, "filter:left:evaluated")).toBe(0);
  expect(occurrences(afterToggle.slice, "filter:solo:evaluated")).toBe(0);
  // Two state literals that select the same predicate: `right`'s `"off"` and
  // `"mixed"` arms are both `flag == "true"`, and `left` names no `"mixed"`
  // arm at all, so it falls through to show-all — which under `"off"` is
  // already what its one `flag == "false"` survivor gets. So a hash flip
  // between them wakes both sweeps, evaluates every row, and writes zero.
  await page.evaluate(() => {
    location.hash = "#/off";
  });
  await expect(page.locator("#right .twin-label")).toHaveText(["R0", "R1"]);
  await expect(page.locator("#left .twin-label")).toHaveText(["L1"]);
  const beforeMixed = await markTrace(page);
  await page.evaluate(() => {
    location.hash = "#/mixed";
  });
  await expect
    .poll(() => page.evaluate(() => globalThis.twinDispose.instrumentation()[1]))
    .toBe(beforeMixed.commits + 1);
  const afterMixed = await readTrace(page);
  expect(writtenCounts(afterMixed.slice, "left")).toEqual([0]);
  expect(writtenCounts(afterMixed.slice, "right")).toEqual([0]);
  expect(occurrences(afterMixed.slice, "dom:filter:left:write")).toBe(0);
  expect(occurrences(afterMixed.slice, "dom:filter:right:write")).toBe(0);
  expect(afterMixed.evaluations).toBe(beforeMixed.evaluations + 2);
  expect(afterMixed.writes).toBe(beforeMixed.writes);
  expect(afterMixed.metrics).toEqual(beforeMixed.metrics);
  await expect(page.locator("#right .twin-label")).toHaveText(["R0", "R1"]);
  await expect(page.locator("#left .twin-label")).toHaveText(["L1"]);
});
