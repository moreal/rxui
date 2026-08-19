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
          <div id="one"></div><div id="two"></div>
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
    "Stable",
    '<img src=x onerror="globalThis.leanrxXss=true">',
  ]);
  await expect(page.locator("#one button").first()).toHaveAttribute("type", "button");

  const hostile = page.locator("#one .counter p").nth(4);
  await expect(hostile).toHaveText('<img src=x onerror="globalThis.leanrxXss=true">');
  await expect(hostile.locator("img")).toHaveCount(0);
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
    "Stable",
    '<img src=x onerror="globalThis.leanrxXss=true">',
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
    "Stable",
    '<img src=x onerror="globalThis.leanrxXss=true">',
  ]);
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => resolve())));
  expect(await page.evaluate(() => globalThis.parityMutations)).toBe(0);
  const instrumentation = await page.evaluate(() => globalThis.leanrxDisposers[0].instrumentation());
  expect(instrumentation.slice(0, 7)).toEqual([0, 1, 2, 2, 1, 3, 2]);
  expect(instrumentation[7]).toEqual([
    "transaction:begin",
    "event:addTwo",
    "source:count:write",
    "source:count:write",
    "source:count:changed",
    "derived:doubled:evaluated",
    "derived:doubled:changed",
    "derived:parity:evaluated",
    "sink:countText:evaluated",
    "dom:countText:write",
    "sink:doubledText:evaluated",
    "dom:doubledText:write",
    "sink:stableText:evaluated",
    "transaction:commit",
  ]);
});

test("nested dispatch batches into the outer transaction", async ({ page }) => {
  await openCounter(page);
  await page.evaluate(() => {
    const snapshot = globalThis.leanrxDisposers[0].instrumentation();
    snapshot[0] = 99;
    snapshot[7].push("consumer:mutation");
  });
  await page.locator("#one button").nth(2).click();
  await expect(page.locator("#one .counter p").first()).toHaveText("Count: 3");
  const instrumentation = await page.evaluate(() => globalThis.leanrxDisposers[0].instrumentation());
  expect(instrumentation.slice(0, 7)).toEqual([0, 1, 2, 2, 1, 3, 2]);
  expect(instrumentation[7].filter((event) => event === "transaction:commit")).toHaveLength(1);
  expect(instrumentation[7].slice(0, 7)).toEqual([
    "transaction:begin",
    "event:nestedAddTwo",
    "event:increment",
    "source:count:write",
    "event:increment",
    "source:count:write",
    "source:count:changed",
  ]);
});

test("write then revert leaves the changed frontier empty", async ({ page }) => {
  await openCounter(page);
  await page.locator("#one button").nth(3).click();
  await expect(page.locator("#one .counter p").first()).toHaveText("Count: 1");
  const instrumentation = await page.evaluate(() => globalThis.leanrxDisposers[0].instrumentation());
  expect(instrumentation.slice(0, 7)).toEqual([0, 1, 2, 0, 0, 0, 0]);
  expect(instrumentation[7]).toEqual([
    "transaction:begin",
    "event:roundTrip",
    "source:count:write",
    "source:count:write",
    "transaction:commit",
  ]);
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
