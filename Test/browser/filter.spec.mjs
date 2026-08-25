import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_FILTER_DIST;
if (!directory) throw new Error("LEANRX_FILTER_DIST is required");

const files = new Set(["FilterLab.mjs", "leanrx_dom.mjs"]);
let server;
let origin;

test.beforeAll(async () => {
  server = createServer(async (request, response) => {
    try {
      const requested = new URL(request.url, "http://localhost").pathname.slice(1);
      if (requested === "") {
        response.setHeader("content-type", "text/html; charset=utf-8");
        response.end("<!doctype html><html lang=\"en\"><head><title>Filter Lab</title></head><body><div id=\"app\"></div></body></html>");
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

async function mountFilter(page) {
  await page.goto(origin);
  await page.evaluate(async () => {
    const { mount } = await import("/FilterLab.mjs");
    globalThis.filterDispose = mount(document.getElementById("app"));
  });
}

function instrumentation(page) {
  return page.evaluate(() => globalThis.filterDispose.instrumentation());
}

test("the initial mount reflects the selected filter into class, aria-pressed, and disabled", async ({ page }) => {
  await mountFilter(page);
  await expect(page.locator("#filter-text")).toHaveText("Filter: all");
  const all = page.getByRole("button", { name: "All" });
  const active = page.getByRole("button", { name: "Active" });
  const completed = page.getByRole("button", { name: "Completed" });
  await expect(all).toHaveClass("selected");
  await expect(all).toHaveAttribute("aria-pressed", "true");
  await expect(active).toHaveClass("");
  await expect(active).toHaveAttribute("aria-pressed", "false");
  await expect(completed).toHaveClass("");
  await expect(completed).toHaveAttribute("aria-pressed", "false");
  await expect(page.locator("#reset")).toBeDisabled();
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("selecting a filter moves the class and aria-pressed selections and enables Reset", async ({ page }) => {
  await mountFilter(page);
  await page.getByRole("button", { name: "Active" }).click();
  await expect(page.locator("#filter-text")).toHaveText("Filter: active");
  await expect(page.getByRole("button", { name: "All" })).toHaveClass("");
  await expect(page.getByRole("button", { name: "All" })).toHaveAttribute("aria-pressed", "false");
  await expect(page.getByRole("button", { name: "Active" })).toHaveClass("selected");
  await expect(page.getByRole("button", { name: "Active" })).toHaveAttribute("aria-pressed", "true");
  await expect(page.locator("#reset")).toBeEnabled();
  await page.locator("#reset").click();
  await expect(page.locator("#filter-text")).toHaveText("Filter: all");
  await expect(page.getByRole("button", { name: "All" })).toHaveClass("selected");
  await expect(page.locator("#reset")).toBeDisabled();
});

test("the sweep evaluates every selection once but writes only the differing values", async ({ page }) => {
  await mountFilter(page);
  const before = await instrumentation(page);
  await page.getByRole("button", { name: "Active" }).click();
  const after = await instrumentation(page);
  // tx[8]/tx[9]: all seven selections depend on the changed filter source,
  // so all seven evaluate; the Completed button's class and aria-pressed
  // values are equal in both states, so exactly five values are written
  // (All class + pressed, Active class + pressed, Reset disabled).
  expect(after[8] - before[8]).toBe(7);
  expect(after[9] - before[9]).toBe(5);
});

test("reselecting the active filter performs no selection work", async ({ page }) => {
  await mountFilter(page);
  await page.getByRole("button", { name: "Active" }).click();
  const before = await instrumentation(page);
  await page.getByRole("button", { name: "Active" }).click();
  const after = await instrumentation(page);
  expect(after[8] - before[8]).toBe(0);
  expect(after[9] - before[9]).toBe(0);
  expect(after[6] - before[6]).toBe(0);
  expect(after[1] - before[1]).toBe(1);
});

test("keyboard activation drives the selections", async ({ page }) => {
  await mountFilter(page);
  await page.getByRole("button", { name: "Completed" }).focus();
  await page.keyboard.press("Enter");
  await expect(page.getByRole("button", { name: "Completed" })).toHaveClass("selected");
  await expect(page.getByRole("button", { name: "Completed" })).toHaveAttribute("aria-pressed", "true");
  await expect(page.locator("#filter-text")).toHaveText("Filter: completed");
});

test("disposal removes the tree and the listeners", async ({ page }) => {
  await mountFilter(page);
  await page.evaluate(() => {
    globalThis.allButton = document.querySelector(".filter-lab button");
    globalThis.filterDispose();
    globalThis.filterDispose();
  });
  await expect(page.locator(".filter-lab")).toHaveCount(0);
  const stillAttached = await page.evaluate(() => {
    globalThis.allButton.dispatchEvent(new Event("click", { bubbles: true }));
    return document.contains(globalThis.allButton);
  });
  expect(stillAttached).toBe(false);
});
