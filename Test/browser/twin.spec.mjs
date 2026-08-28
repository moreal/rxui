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
async function seedBoth(page) {
  await page.getByRole("button", { name: "Seed on" }).click();
  await page.getByRole("button", { name: "Seed off" }).click();
  await expect(page.locator("#left > li")).toHaveCount(2);
  await expect(page.locator("#right > li")).toHaveCount(2);
  await expect(page.locator("#solo > li")).toHaveCount(2);
}

// The trace slice has to be measured from inside the page: the mark is stashed
// on `globalThis` *before* the click so the post-click read can slice from it.
async function markTrace(page) {
  return page.evaluate(() => {
    const tx = globalThis.twinDispose.instrumentation();
    globalThis.twinTraceLength = tx[7].length;
    return {
      commits: tx[1],
      evaluations: tx[8],
      metrics: globalThis.twinDispose.regionInstrumentation(),
    };
  });
}

async function readTrace(page) {
  return page.evaluate(() => {
    const tx = globalThis.twinDispose.instrumentation();
    return {
      commits: tx[1],
      evaluations: tx[8],
      slice: tx[7].slice(globalThis.twinTraceLength),
      metrics: globalThis.twinDispose.regionInstrumentation(),
    };
  });
}

function occurrences(slice, event) {
  return slice.filter((entry) => entry === event).length;
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

test("three filtered regions mount with their own containers", async ({ page }) => {
  await mountTwin(page);
  await expect(page.locator("#left-line")).toHaveText("0 left");
  await seedBoth(page);
  await expect(page.locator("#left-line")).toHaveText("2 left");
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
  await expect(page.locator("#left > li").nth(0)).toBeVisible();
  await expect(page.locator("#left > li").nth(1)).toBeHidden();
  await expect(page.locator("#right > li").nth(0)).toBeHidden();
  await expect(page.locator("#right > li").nth(1)).toBeVisible();
  // `solo` reads `tone`, still `"all"`: it is not woken at all.
  await expect(page.locator("#solo > li").nth(0)).toBeVisible();
  await expect(page.locator("#solo > li").nth(1)).toBeVisible();
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
      evaluations: tx[8],
      metrics: globalThis.twinDispose.regionInstrumentation(),
      hidden: globalThis.twinRows.map((row) => row.hidden),
    };
  });
  // ADR-0079: `tone` drives only `solo`'s sweep. The twins keep the `hidden`
  // values their own field left them with, and neither is re-evaluated.
  await page.getByRole("button", { name: "Tone on" }).click();
  await expect(page.locator("#solo > li").nth(0)).toBeVisible();
  await expect(page.locator("#solo > li").nth(1)).toBeHidden();
  const after = await page.evaluate(() => {
    const tx = globalThis.twinDispose.instrumentation();
    return {
      commits: tx[1],
      evaluations: tx[8],
      slice: tx[7].slice(globalThis.twinTraceLength),
      metrics: globalThis.twinDispose.regionInstrumentation(),
      hidden: globalThis.twinRows.map((row) => row.hidden),
      identical: globalThis.twinRows.every((row) => document.contains(row)),
    };
  });
  expect(after.commits).toBe(before.commits + 1);
  expect(occurrences(after.slice, "filter:solo:evaluated")).toBe(1);
  expect(occurrences(after.slice, "filter:left:evaluated")).toBe(0);
  expect(occurrences(after.slice, "filter:right:evaluated")).toBe(0);
  expect(after.evaluations).toBe(before.evaluations + 1);
  expect(after.hidden).toEqual(before.hidden);
  expect(after.identical).toBe(true);
  expect(after.metrics).toEqual(before.metrics);
  // The unfiltered-by-`tone` twins keep their row count too.
  await expect(page.locator("#left-line")).toHaveText("2 left");
});

test("a region touch alone wakes only that region's sweep", async ({ page }) => {
  await mountTwin(page);
  await seedBoth(page);
  await flipMode(page, "Show on", "#/on");
  const before = await markTrace(page);
  // No field changes: `left`'s sweep wakes on its own touched flag, and the
  // twin sharing its filter field stays asleep.
  await page.getByRole("button", { name: "Add left" }).click();
  await expect(page.locator("#left .twin-label")).toHaveText(["L0", "L1", "L2"]);
  await expect(page.locator("#left > li").nth(2)).toBeVisible();
  const after = await readTrace(page);
  expect(occurrences(after.slice, "filter:left:evaluated")).toBe(1);
  expect(occurrences(after.slice, "filter:right:evaluated")).toBe(0);
  expect(occurrences(after.slice, "filter:solo:evaluated")).toBe(0);
  expect(after.evaluations).toBe(before.evaluations + 1);
  // A removal is the same story from the other side.
  const beforeRemoval = await markTrace(page);
  await page.locator("#left > li").first()
    .getByRole("button", { name: "Remove left" }).click();
  await expect(page.locator("#left .twin-label")).toHaveText(["L1", "L2"]);
  const afterRemoval = await readTrace(page);
  expect(occurrences(afterRemoval.slice, "filter:left:evaluated")).toBe(1);
  expect(occurrences(afterRemoval.slice, "filter:right:evaluated")).toBe(0);
  expect(occurrences(afterRemoval.slice, "filter:solo:evaluated")).toBe(0);
  expect(afterRemoval.evaluations).toBe(beforeRemoval.evaluations + 1);
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
  await expect(page.locator("#left > li").nth(0)).toBeVisible();
  await expect(page.locator("#left > li").nth(1)).toBeHidden();
  await expect(page.locator("#right > li").nth(0)).toBeHidden();
  await expect(page.locator("#right > li").nth(1)).toBeVisible();
  // `tone` is untouched, so `solo`'s own table still shows every row.
  await expect(page.locator("#solo > li").nth(1)).toBeVisible();
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
  await seedBoth(page);
  // ADR-0080: `"mixed"` is named by `right`'s arm table alone. The route's
  // sealed literal set is the declared default plus the *union* of every
  // filter table over `mode`, so `#/mixed` is a legal hash on the strength of
  // the second-declared table — under a first-match rule it would have been
  // rejected purely because `left` is declared first. At runtime the region
  // that names the literal filters, and the twin that does not falls through
  // to show-all, which is exactly what its own arm chain already does.
  await expect(page.locator("#right > li").nth(0)).toBeVisible();
  await expect(page.locator("#right > li").nth(1)).toBeHidden();
  await expect(page.locator("#left > li").nth(0)).toBeVisible();
  await expect(page.locator("#left > li").nth(1)).toBeVisible();
  // `solo` reads `tone`; the routed field never reaches it.
  await expect(page.locator("#solo > li").nth(0)).toBeVisible();
  await expect(page.locator("#solo > li").nth(1)).toBeVisible();
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
  await expect(page.locator("#left > li").nth(0)).toBeHidden();
  await expect(page.locator("#left > li").nth(1)).toBeVisible();
  await expect(page.locator("#right > li").nth(0)).toBeVisible();
  await expect(page.locator("#right > li").nth(1)).toBeHidden();
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
  await expect(page.locator("#left > li").nth(0)).toBeVisible();
  await expect(page.locator("#left > li").nth(1)).toBeVisible();
  await expect(page.locator("#right > li").nth(0)).toBeVisible();
  await expect(page.locator("#right > li").nth(1)).toBeHidden();
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
  // Under `"on"` `right` keeps the `flag == "false"` rows, so R1 alone shows.
  await expect(page.locator("#right > li").nth(0)).toBeHidden();
  await expect(page.locator("#right > li").nth(1)).toBeVisible();
  const before = await page.evaluate(() => {
    const tx = globalThis.twinDispose.instrumentation();
    globalThis.twinTraceLength = tx[7].length;
    globalThis.twinRow = document.querySelectorAll("#right > li")[1];
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
  await page.locator("#right > li").nth(1)
    .getByRole("checkbox", { name: "Flag right" }).check();
  await expect(page.locator("#right > li").nth(1)).toBeHidden();
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
  await expect(page.locator("#left > li").nth(0)).toBeHidden();
  await expect(page.locator("#left > li").nth(1)).toBeVisible();
  await expect(page.locator("#right > li").nth(0)).toBeVisible();
  await expect(page.locator("#right > li").nth(1)).toBeHidden();
  await flipMode(page, "Show all", "#/");
  await page.getByRole("button", { name: "Tone all" }).click();
  await expect(page.locator("#left > li").nth(1)).toBeVisible();
  await expect(page.locator("#right > li").nth(0)).toBeVisible();
  await expect(page.locator("#solo > li").nth(1)).toBeVisible();
  const after = await page.evaluate(() => ({
    metrics: globalThis.twinDispose.regionInstrumentation(),
    identical: globalThis.twinRows.every((row) => document.contains(row)),
    rows: document.querySelectorAll("li").length,
  }));
  expect(after.metrics).toEqual(before);
  expect(after.identical).toBe(true);
  expect(after.rows).toBe(6);
});
