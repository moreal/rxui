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
  const status = root.getByRole("status");
  await expect(rows).toHaveCount(10000);
  await expect(rows.first().getByRole("gridcell")).toHaveCount(1);
  await expect(status).toHaveText("10000 visible / 10000 source");
  await expect(root.locator("img")).toHaveCount(0);
  expect(await page.evaluate(() => globalThis.gridXss)).toBeUndefined();
  expect(await root.locator("[data-lrx-action]").evaluateAll((nodes) =>
    nodes.every((node) => node.matches("button")))).toBe(true);

  const operationMs = {};
  for (const [label, key] of [
    ["Update one row", "update"],
    ["Remove every tenth row", "remove"],
    ["Swap two rows", "swap"],
    ["Toggle odd rows", "filter"],
    ["Toggle sort order", "sort"],
    ["Select row 7777", "select"],
  ]) {
    const started = await page.evaluate(() => performance.now());
    await root.getByRole("button", { name: label }).click();
    operationMs[key] = (await page.evaluate(() => performance.now())) - started;
    if (key === "update") {
      await expect(root.locator('[data-row-id="5000"]')).toHaveText("Row 5000 value 50001");
    } else if (key === "remove") {
      await expect(rows).toHaveCount(9000);
      await expect(root.locator('[data-row-id="0"]')).toHaveCount(0);
    } else if (key === "swap") {
      await expect(rows.first()).toHaveAttribute("data-row-id", "9998");
    } else if (key === "filter") {
      await expect(rows).toHaveCount(5000);
      await expect(rows.first()).toHaveAttribute("data-row-id", "3");
    } else if (key === "sort") {
      await expect(rows.first()).toHaveAttribute("data-row-id", String(expected.firstId));
      await expect(rows.last()).toHaveAttribute("data-row-id", String(expected.lastId));
    } else if (key === "select") {
      await expect(root.locator(`[data-row-id="${expected.selected}"]`))
        .toHaveAttribute("aria-selected", "true");
    }
  }
  await expect(status).toHaveText(`${expected.visibleCount} visible / ${expected.sourceCount} source`);
  await expect(rows).toHaveCount(expected.visibleCount);
  expect(await rows.evaluateAll((nodes) => nodes.every((row) =>
    row.children.length === 1 && row.children[0].getAttribute("role") === "gridcell"))).toBe(true);

  const beforeReselect = await page.evaluate(() => ({
    instrumentation: globalThis.gridDispose.instrumentation(),
    region: globalThis.gridDispose.regionInstrumentation(),
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
      .exclude('[role="grid"] > [role="row"]:not(:first-child)')
      .analyze();
    expect(accessibility.violations).toEqual([]);
  }

  const result = await page.evaluate(({ mountMs: measuredMount, operationMs: measuredOps }) => {
    const rowsNow = [...document.querySelectorAll('[role="row"]')];
    const before = globalThis.gridDispose.instrumentation();
    const region = globalThis.gridDispose.regionInstrumentation();
    const heapBytes = performance.memory?.usedJSHeapSize ?? null;
    const detachedButton = document.querySelector('[data-lrx-action="update"]');
    globalThis.gridDispose();
    globalThis.gridDispose();
    detachedButton.click();
    return {
      mountMs: measuredMount,
      operationMs: measuredOps,
      firstId: Number(rowsNow[0].getAttribute("data-row-id")),
      lastId: Number(rowsNow.at(-1).getAttribute("data-row-id")),
      selected: Number(rowsNow.find((row) => row.getAttribute("aria-selected") === "true")
        ?.getAttribute("data-row-id")),
      count: rowsNow.length,
      instrumentation: before,
      region,
      heapBytes,
      afterDispose: globalThis.gridDispose.instrumentation(),
    };
  }, { mountMs, operationMs });
  expect(result.afterDispose).toEqual(result.instrumentation);
  await expect(root).toHaveCount(0);
  return result;
}

test("@grid keeps all structural strategies logically aligned on 10,000 rows", async ({ page }) => {
  test.setTimeout(180000);
  const full = await runVariant(page, "mountFull", false);
  const delta = await runVariant(page, "mountDelta", false);
  const hybrid = await runVariant(page, "mountHybrid", true);
  const logical = ({ firstId, lastId, selected, count }) => ({ firstId, lastId, selected, count });
  expect(logical(delta)).toEqual(logical(full));
  expect(logical(hybrid)).toEqual(logical(full));
  expect(delta.region[0][5]).toBeGreaterThan(0);
  expect(hybrid.region[0][5]).toBeGreaterThan(0);
  expect(delta.region[0][1]).toBeLessThan(full.region[0][1]);
  console.log(`GRID_MEASUREMENTS ${JSON.stringify({ full, delta, hybrid })}`);
});
