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
  const after = await readTrace(page);
  expect(after.commits).toBe(before.commits + 1);
  expect(occurrences(after.slice, "transaction:commit")).toBe(1);
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
  await page.getByRole("button", { name: "Show on" }).click();
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
  await page.getByRole("button", { name: "Show on" }).click();
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
  const after = await readTrace(page);
  expect(after.commits).toBe(before.commits + 1);
  expect(occurrences(after.slice, "transaction:commit")).toBe(1);
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

test("flipping back restores every region without remounting a row", async ({ page }) => {
  await mountTwin(page);
  await seedBoth(page);
  await page.getByRole("button", { name: "Show on" }).click();
  await page.getByRole("button", { name: "Tone on" }).click();
  const before = await page.evaluate(() => {
    globalThis.twinRows = Array.from(document.querySelectorAll("li"));
    return globalThis.twinDispose.regionInstrumentation();
  });
  await page.getByRole("button", { name: "Show off" }).click();
  await expect(page.locator("#left > li").nth(0)).toBeHidden();
  await expect(page.locator("#left > li").nth(1)).toBeVisible();
  await expect(page.locator("#right > li").nth(0)).toBeVisible();
  await expect(page.locator("#right > li").nth(1)).toBeHidden();
  await page.getByRole("button", { name: "Show all" }).click();
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
