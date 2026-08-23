import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_TABS_DIST;
if (!directory) throw new Error("LEANRX_TABS_DIST is required");

const files = new Set(["DependentTabs.mjs", "leanrx_dom.mjs"]);
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

async function expectPressed(buttons, selected) {
  for (let index = 0; index < 3; index += 1) {
    await expect(buttons.nth(index)).toHaveAttribute(
      "aria-pressed",
      index === selected ? "true" : "false",
    );
  }
}

test("keeps dependent labels, panels, and finite events aligned", async ({ page }) => {
  await page.goto(origin);
  const exports = await page.evaluate(async () => {
    const generated = await import("/DependentTabs.mjs");
    globalThis.tabsDispose = generated.mount(document.getElementById("app"));
    return Object.keys(generated);
  });
  expect(exports).toEqual(["mount"]);

  const buttons = page.locator(".leanrx-tabs button");
  const hostileLabel = '<img src=x onerror="globalThis.tabsLabelXss=true">';
  const hostilePanel = '<img src=x onerror="globalThis.tabsPanelXss=true">';
  const hostileName =
    'Dependent <img src=x onerror="globalThis.tabsNameXss=true"> Tabs';
  await expect(page.locator(".leanrx-tabs h1")).toHaveText(hostileName);
  await expect(buttons).toHaveText(["Overview", "Details", hostileLabel]);
  await expect(page.locator('.leanrx-tabs [role="group"]')).toHaveAttribute(
    "aria-label",
    "Tab selection",
  );
  await expectPressed(buttons, 1);
  const panel = page.locator(".leanrx-tabs p");
  await expect(panel).toHaveText("Shared panel");
  await expect(page.locator(".leanrx-tabs img")).toHaveCount(0);
  expect(
    await page.evaluate(() => [
      globalThis.tabsNameXss,
      globalThis.tabsLabelXss,
      globalThis.tabsPanelXss,
    ]),
  ).toEqual([undefined, undefined, undefined]);

  await page.evaluate(() => {
    const text = document.querySelector(".leanrx-tabs p").firstChild;
    globalThis.equalPanelMutations = 0;
    globalThis.equalPanelObserver = new MutationObserver((records) => {
      globalThis.equalPanelMutations += records.length;
    });
    globalThis.equalPanelObserver.observe(text, { characterData: true });
  });
  await page.keyboard.press("Tab");
  await expect(buttons.nth(0)).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(panel).toHaveText("Shared panel");
  await expectPressed(buttons, 0);
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(resolve)));
  expect(await page.evaluate(() => globalThis.equalPanelMutations)).toBe(0);
  expect(
    (await page.evaluate(() => globalThis.tabsDispose.instrumentation())).slice(0, 7),
  ).toEqual([0, 1, 1, 0, 0, 1, 0]);

  const expected = ["Shared panel", "Shared panel", hostilePanel];
  for (let index = 0; index < expected.length; index += 1) {
    await buttons.nth(index).click();
    await expect(panel).toHaveText(expected[index]);
    await expectPressed(buttons, index);
  }
  expect(await panel.textContent()).not.toBe("undefined");
  const instrumentation = await page.evaluate(() => globalThis.tabsDispose.instrumentation());
  expect(instrumentation.slice(0, 7)).toEqual([0, 4, 4, 0, 0, 3, 1]);
  expect(instrumentation[7].filter((event) => event === "event:select")).toHaveLength(4);
  expect(instrumentation[7].filter((event) => event === "transaction:commit")).toHaveLength(4);

  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("reselecting the active tab suppresses panel work and DOM writes", async ({ page }) => {
  await page.goto(origin);
  await page.evaluate(async () => {
    const { mount } = await import("/DependentTabs.mjs");
    globalThis.tabsDispose = mount(document.getElementById("app"));
    const text = document.querySelector(".leanrx-tabs p").firstChild;
    globalThis.tabsMutations = 0;
    globalThis.tabsObserver = new MutationObserver((records) => {
      globalThis.tabsMutations += records.length;
    });
    globalThis.tabsObserver.observe(text, { characterData: true });
  });
  await page.locator(".leanrx-tabs button").nth(1).click();
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(resolve)));
  await expect(page.locator(".leanrx-tabs p")).toHaveText("Shared panel");
  expect(await page.evaluate(() => globalThis.tabsMutations)).toBe(0);
  const instrumentation = await page.evaluate(() => globalThis.tabsDispose.instrumentation());
  expect(instrumentation.slice(0, 7)).toEqual([0, 1, 1, 0, 0, 0, 0]);
  expect(instrumentation[7]).toEqual([
    "event:select",
    "source:selected:write",
    "transaction:commit",
  ]);
});
