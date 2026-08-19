import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_DIAMOND_DIST;
if (!directory) throw new Error("LEANRX_DIAMOND_DIST is required");

const files = new Set([
  "DiamondLab.mjs",
  "Diamond.expected.json",
  "leanrx_dom.mjs",
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
        response.end("<!doctype html><html lang=\"en\"><head><title>Diamond Lab</title></head><body><div id=\"app\"></div></body></html>");
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

test("batches a diamond without an intermediate fan-in value", async ({ page }) => {
  await page.goto(origin);
  const expectedValues = await page.evaluate(async () => (await fetch("/Diamond.expected.json")).json());
  await page.evaluate(async () => {
    const { mount } = await import("/DiamondLab.mjs");
    globalThis.diamondDispose = mount(document.getElementById("app"));
    const total = document.querySelector(".diamond-lab p:nth-of-type(3)").firstChild;
    globalThis.totalValues = [];
    globalThis.totalObserver = new MutationObserver(() => {
      globalThis.totalValues.push(total.data);
    });
    globalThis.totalObserver.observe(total, { characterData: true });
  });
  await expect(page.locator(".diamond-lab p")).toHaveText([
    `Left: ${expectedValues.initialLeft}`,
    `Right: ${expectedValues.initialRight}`,
    `Total: ${expectedValues.initialTotal}`,
  ]);
  await page.keyboard.press("Tab");
  await expect(page.locator(".diamond-lab button")).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page.locator(".diamond-lab p")).toHaveText([
    `Left: ${expectedValues.finalLeft}`,
    `Right: ${expectedValues.finalRight}`,
    `Total: ${expectedValues.finalTotal}`,
  ]);
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(resolve)));
  expect(await page.evaluate(() => globalThis.totalValues)).toEqual(["Total: 19"]);
  const instrumentation = await page.evaluate(() => globalThis.diamondDispose.instrumentation);
  expect(instrumentation.slice(0, 7)).toEqual([0, 1, 2, 3, 3, 3, 3]);
  const trace = instrumentation[7];
  const left = trace.indexOf("derived:left:evaluated");
  const right = trace.indexOf("derived:right:evaluated");
  const total = trace.indexOf("derived:total:evaluated");
  const sink = trace.indexOf("sink:totalText:evaluated");
  expect(left).toBeGreaterThan(-1);
  expect(right).toBeGreaterThan(left);
  expect(total).toBeGreaterThan(right);
  expect(sink).toBeGreaterThan(total);
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});
