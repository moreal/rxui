import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_NEST_DIST;
if (!directory) throw new Error("LEANRX_NEST_DIST is required");

const files = new Set([
  "NestLab.mjs",
  "Pulse.mjs",
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
        response.end("<!doctype html><html lang=\"en\"><head><title>Nest Lab</title></head><body><div id=\"app\"></div></body></html>");
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

async function mountNest(page) {
  await page.goto(origin);
  await page.evaluate(async () => {
    const { mount } = await import("/NestLab.mjs");
    globalThis.nestDispose = mount(document.getElementById("app"));
  });
}

test("the child component mounts inline in document order with its prop", async ({ page }) => {
  await mountNest(page);
  await expect(page.locator("#nest-text")).toHaveText("Clicks: 0");
  await expect(page.locator("#pulse-text")).toHaveText("Beats: 0");
  await expect(page.locator("#pulse-title")).toHaveText("Pulse child");
  const order = await page.evaluate(() =>
    Array.from(document.querySelector(".nest-lab").children).map((node) =>
      node.className || node.tagName.toLowerCase(),
    ),
  );
  expect(order).toEqual(["h1", "button", "p", "button", "ul", "pulse"]);
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("parent and child state stay independent", async ({ page }) => {
  await mountNest(page);
  await page.getByRole("button", { name: "Bump" }).click();
  await page.getByRole("button", { name: "Bump" }).click();
  await expect(page.locator("#nest-text")).toHaveText("Clicks: 2");
  await expect(page.locator("#pulse-text")).toHaveText("Beats: 0");
  await page.getByRole("button", { name: "Pulse" }).click();
  await expect(page.locator("#pulse-text")).toHaveText("Beats: 1");
  await expect(page.locator("#nest-text")).toHaveText("Clicks: 2");
});

test("the keyed roster appends rows with monotone labels", async ({ page }) => {
  await mountNest(page);
  await expect(page.locator("#roster > li")).toHaveCount(0);
  await page.getByRole("button", { name: "Add item" }).click();
  await page.getByRole("button", { name: "Add item" }).click();
  await page.getByRole("button", { name: "Add item" }).click();
  await expect(page.locator("#roster > li .roster-label")).toHaveText([
    "Item 0", "Item 1", "Item 2",
  ]);
});

test("the row button removes exactly its own row through delegation", async ({ page }) => {
  await mountNest(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await add.click();
  await page.locator("#roster > li").nth(1).getByRole("button", { name: "Remove row" }).click();
  await expect(page.locator("#roster > li .roster-label")).toHaveText([
    "Item 0", "Item 2",
  ]);
  await add.click();
  await expect(page.locator("#roster > li .roster-label")).toHaveText([
    "Item 0", "Item 2", "Item 3",
  ]);
});

test("clicking row text dispatches no delegated action", async ({ page }) => {
  await mountNest(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await page.locator("#roster > li .roster-label").first().click();
  await page.locator("#roster").click();
  await expect(page.locator("#roster > li")).toHaveCount(2);
  const regionMetrics = await page.evaluate(() =>
    globalThis.nestDispose.regionInstrumentation(),
  );
  expect(regionMetrics.length).toBe(1);
  expect(regionMetrics[0][0]).toBe(2);
});

test("disposing the parent disposes the child, roster, and listeners", async ({ page }) => {
  await mountNest(page);
  await page.getByRole("button", { name: "Pulse" }).click();
  await page.getByRole("button", { name: "Add item" }).click();
  await expect(page.locator("#pulse-text")).toHaveText("Beats: 1");
  await expect(page.locator("#roster > li")).toHaveCount(1);
  await page.evaluate(() => {
    globalThis.pulseButton = document.querySelector(".pulse button");
    globalThis.nestDispose();
    globalThis.nestDispose();
  });
  await expect(page.locator(".nest-lab")).toHaveCount(0);
  await expect(page.locator(".pulse")).toHaveCount(0);
  await expect(page.locator("#roster")).toHaveCount(0);
  const stillAttached = await page.evaluate(() => {
    globalThis.pulseButton.dispatchEvent(new Event("click", { bubbles: true }));
    return document.contains(globalThis.pulseButton);
  });
  expect(stillAttached).toBe(false);
});
