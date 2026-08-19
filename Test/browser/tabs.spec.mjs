import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_TABS_DIST;
if (!directory) throw new Error("LEANRX_TABS_DIST is required");

const files = new Set(["DependentTabs.mjs", "leanrx_dom.mjs", "leanrx_host.mjs"]);
let server;
let origin;

test.beforeAll(async () => {
  server = createServer(async (request, response) => {
    try {
      const requested = new URL(request.url, "http://localhost").pathname.slice(1);
      if (requested === "") {
        response.setHeader("content-type", "text/html; charset=utf-8");
        response.end("<!doctype html><html lang=\"en\"><head><title>Dependent Tabs</title></head><body><div id=\"app\"></div></body></html>");
      } else if (files.has(requested)) {
        response.setHeader("content-type", "text/javascript; charset=utf-8");
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

test("keeps dependent labels, panels, and finite events aligned", async ({ page }) => {
  await page.goto(origin);
  const exports = await page.evaluate(async () => {
    const generated = await import("/DependentTabs.mjs");
    globalThis.tabsDispose = generated.mount(document.getElementById("app"));
    return Object.keys(generated);
  });
  expect(exports).toEqual(["mount"]);

  const buttons = page.locator(".leanrx-tabs button");
  await expect(buttons).toHaveText(["Overview", "Details", "History"]);
  const panel = page.locator(".leanrx-tabs p");
  await expect(panel).toHaveText("Details panel");

  await page.keyboard.press("Tab");
  await expect(buttons.nth(0)).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(panel).toHaveText("Overview panel");

  const expected = ["Overview panel", "Details panel", "History panel"];
  for (let index = 0; index < expected.length; index += 1) {
    await buttons.nth(index).click();
    await expect(panel).toHaveText(expected[index]);
  }
  expect(await panel.textContent()).not.toBe("undefined");
  const instrumentation = await page.evaluate(() => globalThis.tabsDispose.instrumentation());
  expect(instrumentation.slice(0, 7)).toEqual([0, 4, 4, 0, 0, 4, 4]);
  expect(instrumentation[7].filter((event) => event === "event:select")).toHaveLength(4);
  expect(instrumentation[7].filter((event) => event === "transaction:commit")).toHaveLength(4);

  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});
