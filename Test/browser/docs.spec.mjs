import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_DOCS_DIST;
if (!directory) throw new Error("LEANRX_DOCS_DIST is required");

const files = new Set([
  "index.html",
  "styles.css",
  "LeanRxDocs.mjs",
  "LeanRxDocs.graph.html",
  "leanrx_dom.mjs",
  "leanrx_host.mjs",
]);
let server;
let origin;

test.beforeAll(async () => {
  server = createServer(async (request, response) => {
    try {
      const requested = new URL(request.url, "http://localhost").pathname.slice(1) ||
        "index.html";
      if (!files.has(requested)) {
        response.statusCode = 404;
        response.end("not found");
        return;
      }
      response.setHeader("content-type",
        requested.endsWith(".mjs") ? "text/javascript; charset=utf-8" :
          requested.endsWith(".css") ? "text/css; charset=utf-8" :
            "text/html; charset=utf-8");
      response.end(await readFile(path.join(directory, requested)));
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

test("dogfoods all seven pages with safe text, keyboard access, and exact work", async ({ page }) => {
  await page.goto(origin);
  const title = page.locator(".leanrx-docs h1");
  const body = page.locator(".docs-body");
  const buttons = page.locator(".docs-navigation button");
  await expect(title).toHaveText("Introduction");
  await expect(buttons).toHaveCount(7);
  expect(await buttons.evaluateAll((values) =>
    values.every((value) => value.getAttribute("type") === "button"),
  )).toBe(true);

  await buttons.nth(1).focus();
  await expect(buttons.nth(1)).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(title).toHaveText("Counter");
  await buttons.nth(2).click();
  await expect(title).toHaveText("Static graph");
  await buttons.nth(3).click();
  await expect(title).toHaveText("Dependent Tabs");
  await buttons.nth(4).click();
  await expect(title).toHaveText("Effects and resources");
  await buttons.nth(5).click();
  await expect(title).toHaveText("Limitations");
  await expect(body).toContainText("no URL router");
  await expect(body).toContainText('<img src=x onerror="globalThis.leanrxDocsXss=true">');
  await expect(body.locator("img")).toHaveCount(0);
  expect(await page.evaluate(() => globalThis.leanrxDocsXss)).toBeUndefined();
  await buttons.nth(6).click();
  await expect(title).toHaveText("Generated graph viewer");
  await expect(body).toContainText("digraph LeanRx");
  await buttons.nth(0).click();
  await expect(title).toHaveText("Introduction");

  const instrumentation = await page.evaluate(() =>
    globalThis.leanrxDocsDispose.instrumentation(),
  );
  expect(instrumentation.slice(0, 7)).toEqual([0, 7, 7, 21, 21, 21, 21]);
  expect(instrumentation[7].filter((entry) => entry === "transaction:commit")).toHaveLength(7);

  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);

  const graphHtml = await (await page.request.get(`${origin}/LeanRxDocs.graph.html`)).text();
  expect(graphHtml).toContain("<!doctype html>");
  expect(graphHtml).toContain("Certified schedule");
  expect(graphHtml).not.toContain("<script");
});

test("mounts independently and disposes listeners idempotently", async ({ page }) => {
  await page.goto(origin);
  const result = await page.evaluate(async () => {
    const second = document.createElement("div");
    second.id = "second";
    document.body.append(second);
    const { mount } = await import("/LeanRxDocs.mjs");
    const disposeSecond = mount(second);
    const firstButton = document.querySelector("#app button");
    const secondButton = document.querySelector("#second button:nth-of-type(2)");
    secondButton.click();
    const firstTitle = document.querySelector("#app h1").textContent;
    const secondTitle = document.querySelector("#second h1").textContent;
    const before = disposeSecond.instrumentation();
    disposeSecond();
    disposeSecond();
    secondButton.click();
    const after = disposeSecond.instrumentation();
    globalThis.leanrxDocsDispose();
    globalThis.leanrxDocsDispose();
    firstButton.click();
    return { firstTitle, secondTitle, before, after };
  });
  expect(result.firstTitle).toBe("Introduction");
  expect(result.secondTitle).toBe("Counter");
  expect(result.after).toEqual(result.before);
  await expect(page.locator(".leanrx-docs")).toHaveCount(0);
});
