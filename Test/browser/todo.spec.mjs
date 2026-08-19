import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_TODO_DIST;
if (!directory) throw new Error("LEANRX_TODO_DIST is required");

const files = new Set([
  "TodoMVC.mjs",
  "TodoMVC.expected.json",
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
        response.end("<!doctype html><html lang=\"en\"><head><title>TodoMVC</title></head><body><div id=\"app\"></div></body></html>");
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

test("preserves keyed identity, focus, routing, and local region ownership", async ({ page }) => {
  await page.goto(origin);
  const expected = await page.evaluate(async () => (await fetch("/TodoMVC.expected.json")).json());
  await page.evaluate(async () => {
    const { mount } = await import("/TodoMVC.mjs");
    globalThis.todoDispose = mount(document.getElementById("app"));
    globalThis.todoRoot = document.querySelector(".leanrx-todo");
  });
  const root = page.locator(".leanrx-todo");
  const newInput = root.locator('input[aria-label="New todo"]');
  const rows = root.locator("li");
  const filters = root.locator('[aria-label="Todo filters"] button');
  const status = root.locator('[role="status"]');
  await expect(rows).toHaveCount(0);
  await expect(filters).toHaveCount(3);
  await expect(status).toHaveText("0 items left");

  const hostile = '<img src=x onerror="globalThis.todoXss=true">';
  await newInput.fill(hostile);
  await newInput.press("Enter");
  await newInput.fill("Second");
  await root.getByRole("button", { name: "Add" }).click();
  await expect(rows).toHaveCount(2);
  await expect(rows.nth(0).locator("span")).toHaveText(hostile);
  await expect(root.locator("img")).toHaveCount(0);
  expect(await page.evaluate(() => globalThis.todoXss)).toBeUndefined();

  await rows.nth(0).evaluate((node) => { globalThis.todoFirstRow = node; });
  await rows.nth(1).evaluate((node) => { globalThis.todoSecondRow = node; });
  const childMutations = await rows.nth(0).evaluate((row) => {
    globalThis.todoChildMutations = 0;
    globalThis.todoObserver = new MutationObserver((records) => {
      globalThis.todoChildMutations += records.filter((record) => record.type === "childList").length;
    });
    globalThis.todoObserver.observe(row, { childList: true, subtree: true });
    return 0;
  });
  expect(childMutations).toBe(0);
  await rows.nth(0).locator('input[type="checkbox"]').check();
  expect(await page.evaluate(() => document.querySelector(".leanrx-todo") === globalThis.todoRoot))
    .toBe(true);
  expect(await rows.nth(0).evaluate((node) => node === globalThis.todoFirstRow)).toBe(true);
  expect(await page.evaluate(() => globalThis.todoChildMutations)).toBe(0);
  await expect(status).toHaveText("1 items left");

  await filters.filter({ hasText: "Active" }).click();
  await expect(rows).toHaveCount(1);
  expect(await rows.nth(0).evaluate((node) => node === globalThis.todoSecondRow)).toBe(true);
  await filters.filter({ hasText: "All" }).click();
  await expect(rows).toHaveCount(2);
  expect(await rows.nth(1).evaluate((node) => node === globalThis.todoSecondRow)).toBe(true);

  await rows.nth(1).getByRole("button", { name: "Edit" }).click();
  const editInput = rows.nth(1).locator('input[aria-label="Edit todo"]');
  await editInput.focus();
  await editInput.fill(" Edited ");
  await editInput.evaluate((node) => { globalThis.todoEditInput = node; });
  await root.getByRole("button", { name: "Reverse order" }).evaluate((button) => button.click());
  await expect(rows.nth(0)).toHaveAttribute("data-todo-id", "1");
  expect(await rows.nth(0).evaluate((node) => node === globalThis.todoSecondRow)).toBe(true);
  expect(await rows.nth(0).locator('input[aria-label="Edit todo"]').evaluate(
    (node) => node === globalThis.todoEditInput,
  )).toBe(true);
  expect(await page.evaluate(() => document.activeElement?.getAttribute("aria-label")))
    .toBe("Edit todo");
  await rows.nth(0).locator('input[aria-label="Edit todo"]').press("Enter");
  await expect(rows.nth(0).locator("span")).toHaveText("Edited");

  const logicalRows = await rows.evaluateAll((nodes) => nodes.map((node) => ({
    id: Number(node.getAttribute("data-todo-id")),
    title: node.querySelector("span")?.textContent ?? "",
    completed: node.classList.contains("completed"),
  })));
  expect(logicalRows).toEqual(expected.rows);
  await expect(status).toHaveText(`${expected.remaining} items left`);
  await expect(filters.filter({ hasText: "All" })).toHaveAttribute("aria-pressed", "true");

  await rows.nth(1).getByRole("button", { name: "Delete" }).click();
  await expect(rows).toHaveCount(1);
  await expect(rows.nth(0)).toHaveAttribute("data-todo-id", "1");
  await rows.nth(0).locator('input[type="checkbox"]').check();
  await root.getByRole("button", { name: "Clear completed" }).click();
  await expect(rows).toHaveCount(0);
  await expect(status).toHaveText("0 items left");

  const instrumentation = await page.evaluate(() => globalThis.todoDispose.instrumentation());
  expect(instrumentation[0]).toBe(0);
  expect(instrumentation[3]).toBe(0);
  expect(instrumentation[4]).toBe(0);
  expect(instrumentation[1]).toBeGreaterThan(0);
  expect(instrumentation[5]).toBeGreaterThan(0);
  const regions = await page.evaluate(() => globalThis.todoDispose.regionInstrumentation());
  expect(regions).toHaveLength(2);
  expect(regions[0][0]).toBeGreaterThan(1);
  expect(regions[0][2]).toBeGreaterThan(0);
  expect(regions[0][3]).toBeGreaterThan(0);
  expect(regions[1][0]).toBe(3);
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);

  await page.evaluate(() => {
    globalThis.todoObserver.disconnect();
    globalThis.todoDispose();
    globalThis.todoDispose();
  });
  await expect(root).toHaveCount(0);
});
