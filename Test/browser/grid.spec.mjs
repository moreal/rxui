import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_GRID_DIST;
if (!directory) throw new Error("LEANRX_GRID_DIST is required");

const files = new Set([
  "DataGrid.mjs",
  "DataGrid.expected.json",
  "leanrx_dom.mjs",
  "leanrx_region.mjs",
  "leanrx_host.mjs",
]);
let server;
let origin;

test.beforeAll(async () => {
  server = createServer(async (request, response) => {
    try {
      const requested = new URL(request.url, "http://localhost").pathname.slice(1);
      if (requested === "") {
        response.setHeader("content-type", "text/html; charset=utf-8");
        response.end("<!doctype html><html lang=\"en\"><head><title>Data Grid</title></head><body><div id=\"app\"></div></body></html>");
      } else if (files.has(requested)) {
        response.setHeader(
          "content-type",
          requested.endsWith(".json") ? "application/json" : "text/javascript",
        );
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

function sampledBytes(node) {
  return (node.selfSize ?? 0) + (node.children ?? []).reduce(
    (total, child) => total + sampledBytes(child),
    0,
  );
}

async function runVariant(page, exportName, checkAccessibility) {
  await page.goto(origin);
  const expected = await page.evaluate(async () => (await fetch("/DataGrid.expected.json")).json());
  const mountMs = await page.evaluate(async (name) => {
    const module = await import("/DataGrid.mjs");
    const started = performance.now();
    globalThis.gridDispose = module[name](document.getElementById("app"));
    return performance.now() - started;
  }, exportName);
  const root = page.locator(".leanrx-grid");
  const rows = root.getByRole("row");
  const controls = root.getByRole("group", { name: "Grid operations" });
  const table = root.getByRole("table", { name: "10,000 row experiment" });
  const status = root.getByRole("status");
  await expect(rows).toHaveCount(0);
  await expect(controls).toHaveCount(1);
  await expect(table).toHaveCount(1);
  await expect(status).toHaveText("0 visible / 0 source");
  await expect(root.locator("img")).toHaveCount(0);
  expect(await page.evaluate(() => globalThis.gridXss)).toBeUndefined();
  expect(await root.locator("[data-lrx-action]").evaluateAll((nodes) =>
    nodes.every((node) => node.matches("button")))).toBe(true);
  const initiallyDisabled = [
    root.getByRole("button", { name: "Update one row" }),
    root.getByRole("button", { name: "Swap rows 1 and 9998" }),
    root.getByRole("button", { name: "Select row 7777" }),
  ];
  const beforeInvalidActions = await page.evaluate(() => globalThis.gridDispose.instrumentation());
  for (const button of initiallyDisabled) {
    await expect(button).toBeDisabled();
    await button.evaluate((element) => element.click());
  }
  expect(await page.evaluate(() => globalThis.gridDispose.instrumentation()))
    .toEqual(beforeInvalidActions);

  const heapProfiler = await page.context().newCDPSession(page);
  await heapProfiler.send("HeapProfiler.enable");
  await heapProfiler.send("HeapProfiler.startSampling", { samplingInterval: 32768 });
  const operationMs = {};
  for (const [label, key] of [
    ["Create 10000 rows", "create"],
    ["Update one row", "update"],
    ["Remove rows divisible by 10", "remove"],
    ["Swap rows 1 and 9998", "swap"],
    ["Toggle odd rows", "filter"],
    ["Toggle sort order", "sort"],
    ["Select row 7777", "select"],
  ]) {
    const button = root.getByRole("button", { name: label });
    operationMs[key] = await button.evaluate((element) => {
      const started = performance.now();
      element.click();
      return performance.now() - started;
    });
    if (key === "create") {
      await expect(rows).toHaveCount(10000);
      expect(await rows.evaluateAll((nodes) => nodes.every(
        (row, index) => Number(row.getAttribute("data-row-id")) === index,
      ))).toBe(true);
      await expect(rows.first().getByRole("cell")).toHaveCount(1);
      await expect(root.getByRole("button", { name: "Update one row" })).toBeEnabled();
      await expect(root.getByRole("button", { name: "Swap rows 1 and 9998" })).toBeEnabled();
      await expect(root.getByRole("button", { name: "Select row 7777" })).toBeEnabled();
    } else if (key === "update") {
      await expect(root.locator('[data-row-id="5000"]')).toHaveText("Row 5000 value 50001");
    } else if (key === "remove") {
      await expect(rows).toHaveCount(9000);
      await expect(root.locator('[data-row-id="0"]')).toHaveCount(0);
      expect(await rows.evaluateAll((nodes) => nodes.every(
        (row) => Number(row.getAttribute("data-row-id")) % 10 !== 0,
      ))).toBe(true);
      const update = root.getByRole("button", { name: "Update one row" });
      await expect(update).toBeDisabled();
      const beforeDisabledClick = await page.evaluate(() => globalThis.gridDispose.instrumentation());
      await update.evaluate((element) => element.click());
      expect(await page.evaluate(() => globalThis.gridDispose.instrumentation()))
        .toEqual(beforeDisabledClick);
    } else if (key === "swap") {
      await expect(rows.first()).toHaveAttribute("data-row-id", "9998");
      await expect(rows.nth(8998)).toHaveAttribute("data-row-id", "1");
    } else if (key === "filter") {
      await expect(rows).toHaveCount(5000);
      await expect(rows.first()).toHaveAttribute("data-row-id", "3");
      expect(await rows.evaluateAll((nodes) => nodes.every(
        (row) => Number(row.getAttribute("data-row-id")) % 2 === 1,
      ))).toBe(true);
    } else if (key === "sort") {
      await expect(rows.first()).toHaveAttribute("data-row-id", String(expected.firstId));
      await expect(rows.last()).toHaveAttribute("data-row-id", String(expected.lastId));
    } else if (key === "select") {
      await expect(root.locator(`[data-row-id="${expected.selected}"]`))
        .toHaveAttribute("aria-current", "true");
    }
  }
  const allocationProfile = await heapProfiler.send("HeapProfiler.stopSampling");
  await heapProfiler.detach();
  const sampledAllocationBytes = sampledBytes(allocationProfile.profile.head);
  await expect(status).toHaveText(`${expected.visibleCount} visible / ${expected.sourceCount} source`);
  await expect(rows).toHaveCount(expected.visibleCount);
  expect(await rows.evaluateAll((nodes) => nodes.every((row) =>
    row.children.length === 1 && row.children[0].getAttribute("role") === "cell"))).toBe(true);

  const beforeReselect = await page.evaluate(() => ({
    instrumentation: globalThis.gridDispose.instrumentation(),
    region: globalThis.gridDispose.regionInstrumentation(),
    gridWork: globalThis.gridDispose.gridInstrumentation(),
  }));
  await root.getByRole("button", { name: "Select row 7777" }).click();
  const afterReselect = await page.evaluate(() => ({
    instrumentation: globalThis.gridDispose.instrumentation(),
    region: globalThis.gridDispose.regionInstrumentation(),
  }));
  expect(afterReselect.instrumentation.slice(3, 7)).toEqual(
    beforeReselect.instrumentation.slice(3, 7),
  );
  expect(afterReselect.region).toEqual(beforeReselect.region);

  if (checkAccessibility) {
    // Every row is checked structurally above. Axe covers the complete unique UI
    // and one populated representative row without re-running identical rules
    // over another 4,999 generated siblings.
    const accessibility = await new AxeBuilder({ page })
      .exclude('[role="table"] > [role="row"]:not(:first-child)')
      .analyze();
    expect(accessibility.violations).toEqual([]);
  }

  const result = await page.evaluate(({ mountMs: measuredMount, operationMs: measuredOps }) => {
    const rowsNow = [...document.querySelectorAll('[role="row"]')];
    const heapBytes = performance.memory?.usedJSHeapSize ?? null;
    return {
      mountMs: measuredMount,
      operationMs: measuredOps,
      firstId: Number(rowsNow[0].getAttribute("data-row-id")),
      lastId: Number(rowsNow.at(-1).getAttribute("data-row-id")),
      selected: Number(rowsNow.find((row) => row.getAttribute("aria-current") === "true")
        ?.getAttribute("data-row-id")),
      count: rowsNow.length,
      rows: rowsNow.map((row) => [
        Number(row.getAttribute("data-row-id")),
        row.textContent,
        row.getAttribute("aria-current") === "true",
      ]),
      heapBytes,
    };
  }, { mountMs, operationMs });
  result.instrumentation = beforeReselect.instrumentation;
  result.region = beforeReselect.region;
  result.gridWork = beforeReselect.gridWork;
  result.sampledAllocationBytes = sampledAllocationBytes;
  expect(result.rows).toEqual(expected.rows);
  delete result.rows;

  if (checkAccessibility) {
    const createButton = root.getByRole("button", { name: "Create 10000 rows" });
    await createButton.focus();
    await page.keyboard.press("Enter");
    await expect(rows).toHaveCount(10000);
  }

  const afterKeyboard = await page.evaluate(() => globalThis.gridDispose.instrumentation());
  const detachedButton = await root.getByRole("button", { name: "Update one row" }).elementHandle();
  await page.evaluate(() => {
    globalThis.gridDispose();
    globalThis.gridDispose();
  });
  await detachedButton.evaluate((element) => element.click());
  expect(await page.evaluate(() => globalThis.gridDispose.instrumentation())).toEqual(afterKeyboard);
  await expect(root).toHaveCount(0);
  return result;
}

test("@grid keeps all structural strategies logically aligned on 10,000 rows", async ({ page }, testInfo) => {
  test.setTimeout(180000);
  const variants = [
    ["full", "mountFull"],
    ["delta", "mountDelta"],
    ["hybrid", "mountHybrid"],
  ];
  const rotation = testInfo.repeatEachIndex % variants.length;
  const order = variants.slice(rotation).concat(variants.slice(0, rotation));
  const results = {};
  const pageErrors = [];
  page.on("pageerror", (error) => pageErrors.push(String(error)));
  for (const [kind, exportName] of order) {
    results[kind] = await runVariant(page, exportName, kind === "hybrid");
  }
  const { full, delta, hybrid } = results;
  const logical = ({ firstId, lastId, selected, count }) => ({ firstId, lastId, selected, count });
  expect(logical(delta)).toEqual(logical(full));
  expect(logical(hybrid)).toEqual(logical(full));
  expect(pageErrors).toEqual([]);
  expect(full.instrumentation).toEqual([
    0, 7, 11, 7, 7, 43007, 40009,
    ["create", "update", "remove", "swap", "filter", "sort", "select"],
    0, 0,
  ]);
  expect(delta.instrumentation).toEqual([
    0, 7, 11, 7, 7, 10009, 40009,
    ["create", "update", "remove", "swap", "filter", "sort", "select"],
    0, 0,
  ]);
  expect(hybrid.instrumentation).toEqual([
    0, 7, 11, 7, 7, 19009, 40009,
    ["create", "update", "remove", "swap", "filter", "sort", "select"],
    0, 0,
  ]);
  expect(full.region).toEqual([[10000, 43000, 23997, 5000]]);
  expect(delta.region).toEqual([[10000, 10002, 15001, 5000, 3, 1007, 21007]]);
  expect(hybrid.region).toEqual([[10000, 19002, 15001, 5000, 4, 4, 29004]]);
  expect(full.gridWork).toEqual([65000, 37000, 0]);
  expect(delta.gridWork).toEqual([28000, 70000, 10000]);
  expect(hybrid.gridWork).toEqual([37000, 70000, 10000]);
  expect(delta.region[0][5]).toBeGreaterThan(0);
  expect(hybrid.region[0][5]).toBeGreaterThan(0);
  expect(delta.region[0][1]).toBeLessThan(full.region[0][1]);
  console.log(`GRID_MEASUREMENTS ${JSON.stringify(results)}`);
});
