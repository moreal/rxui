import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_BROWSER_DIST;
if (!directory) throw new Error("LEANRX_BROWSER_DIST is required");

const files = new Set(["Counter.mjs", "leanrx_dom.mjs", "leanrx_host.mjs"]);
let server;
let origin;

test.beforeAll(async () => {
  server = createServer(async (request, response) => {
    try {
      const requested = new URL(request.url, "http://localhost").pathname.slice(1);
      if (requested === "") {
        response.setHeader("content-type", "text/html; charset=utf-8");
        response.end(`<!doctype html>
          <html lang="en"><head><title>LeanRx Counter test</title></head><body>
          <div id="one"></div><div id="two"></div><div id="hostile"></div>
          </body></html>`);
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
  const address = server.address();
  origin = `http://127.0.0.1:${address.port}`;
});

test.afterAll(async () => {
  await new Promise((resolve, reject) =>
    server.close((error) => (error ? reject(error) : resolve())),
  );
});

async function openCounter(page, targets = ["one"]) {
  await page.goto(origin);
  await page.evaluate(async (mountTargets) => {
    const { mount } = await import("/Counter.mjs");
    globalThis.leanrxDisposers = mountTargets.map((id) =>
      mount(document.getElementById(id)),
    );
  }, targets);
}

test("mounts initial DOM, uses safe text, and passes accessibility scan", async ({ page }) => {
  await openCounter(page);
  await expect(page.locator("#one .counter p")).toHaveText([
    "Count: 1",
    "Doubled: 2",
    "Parity: odd",
  ]);
  await expect(page.locator("#one button").first()).toHaveAttribute("type", "button");

  const hostile = '<img src=x onerror="globalThis.leanrxXss=true">';
  await page.evaluate(async (text) => {
    const { createText, append } = await import("/leanrx_dom.mjs");
    append(document.querySelector("#one main"), document.getElementById("hostile"));
    append(document.getElementById("hostile"), createText(text));
  }, hostile);
  await expect(page.locator("#hostile")).toHaveText(hostile);
  await expect(page.locator("#hostile img")).toHaveCount(0);
  expect(await page.evaluate(() => globalThis.leanrxXss)).toBeUndefined();

  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("increment updates count, doubled, and parity with keyboard activation", async ({ page }) => {
  await openCounter(page);
  await page.keyboard.press("Tab");
  await expect(page.locator("#one button").first()).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page.locator("#one .counter p")).toHaveText([
    "Count: 2",
    "Doubled: 4",
    "Parity: even",
  ]);
});

test("add two suppresses the unchanged parity text write", async ({ page }) => {
  await openCounter(page);
  await page.evaluate(() => {
    const parity = document.querySelector("#one .counter p:nth-of-type(3)").firstChild;
    globalThis.parityMutations = 0;
    const observer = new MutationObserver((records) => {
      globalThis.parityMutations += records.length;
    });
    observer.observe(parity, { characterData: true });
    globalThis.parityObserver = observer;
  });
  await page.locator("#one button").nth(1).click();
  await expect(page.locator("#one .counter p")).toHaveText([
    "Count: 3",
    "Doubled: 6",
    "Parity: odd",
  ]);
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => resolve())));
  expect(await page.evaluate(() => globalThis.parityMutations)).toBe(0);
});

test("mount instances are isolated and disposal is idempotent", async ({ page }) => {
  await openCounter(page, ["one", "two"]);
  await page.locator("#one button").first().click();
  await expect(page.locator("#one .counter p").first()).toHaveText("Count: 2");
  await expect(page.locator("#two .counter p").first()).toHaveText("Count: 1");

  const detachedText = await page.evaluate(() => {
    const root = document.querySelector("#one .counter");
    const button = root.querySelector("button");
    const countText = root.querySelector("p").firstChild;
    globalThis.leanrxDisposers[0]();
    globalThis.leanrxDisposers[0]();
    button.click();
    return countText.data;
  });
  expect(detachedText).toBe("Count: 2");
  await expect(page.locator("#one .counter")).toHaveCount(0);
  await expect(page.locator("#two .counter")).toHaveCount(1);
});
