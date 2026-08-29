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
  "leanrx_form_events.mjs",
  "leanrx_region.mjs",
  "leanrx_unkeyed_region.mjs",
]);
let server;
let origin;

function logicalProjection(root) {
  const element = (tag, attributes, children) => ({ kind: "element", tag, attributes, children });
  const text = (value) => ({ kind: "text", value });
  const rows = [...root.querySelectorAll("ul > li")];
  const selectedFilter = root.querySelector('[aria-label="Todo filters"] [aria-pressed="true"]');
  return element("main", [["class", root.getAttribute("class")]], [
    element("h1", [], [text(root.querySelector("h1").textContent)]),
    element("input", [["value", root.querySelector('[aria-label="New todo"]').value]], []),
    element("ul", [], rows.map((row) => {
      const editInput = row.querySelector('[aria-label="Edit todo"]');
      const title = editInput?.value ?? row.querySelector("span")?.textContent ?? "";
      return element("li", [
        ["data-key", row.getAttribute("data-todo-id")],
        ["class", row.getAttribute("class")],
        ["data-editing", editInput ? "true" : "false"],
      ], [text(title)]);
    })),
    element("footer", [["filter", selectedFilter?.getAttribute("data-lrx-key") ?? ""]], [
      text(root.querySelector('[role="status"]').textContent),
      text(`${rows.filter((row) => row.classList.contains("completed")).length} completed`),
    ]),
  ]);
}

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
  await expect(rows.nth(0).getByRole("checkbox", { name: hostile })).toBeVisible();
  await expect(root.locator("img")).toHaveCount(0);
  expect(await page.evaluate(() => globalThis.todoXss)).toBeUndefined();
  expect(await root.locator("[data-lrx-action]").evaluateAll((nodes) =>
    nodes.every((node) => node.matches("button, input")))).toBe(true);
  const populatedAccessibility = await new AxeBuilder({ page }).analyze();
  expect(populatedAccessibility.violations).toEqual([]);

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

  await rows.nth(1).locator(".todo-view").evaluate((node) => {
    globalThis.todoOldViewBranch = node;
  });
  await rows.nth(1).getByRole("button", { name: "Edit" }).click();
  expect(await page.evaluate(() => globalThis.todoOldViewBranch.isConnected)).toBe(false);
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
  const writesBeforeSave = await page.evaluate(() => globalThis.todoDispose.instrumentation()[2]);
  await rows.nth(0).locator('input[aria-label="Edit todo"]').press("Enter");
  const writesAfterSave = await page.evaluate(() => globalThis.todoDispose.instrumentation()[2]);
  expect(writesAfterSave - writesBeforeSave).toBe(4);
  expect(await page.evaluate(() => globalThis.todoEditInput.isConnected)).toBe(false);
  await expect(rows.nth(0).locator("span")).toHaveText("Edited");

  expect(await root.evaluate(logicalProjection)).toEqual(expected.logical);
  await expect(status).toHaveText("1 items left");
  await expect(filters.filter({ hasText: "All" })).toHaveAttribute("aria-pressed", "true");

  await filters.filter({ hasText: "Completed" }).click();
  await expect(rows).toHaveCount(1);
  await expect(rows.nth(0)).toHaveAttribute("data-todo-id", "0");
  await filters.filter({ hasText: "All" }).click();
  await expect(rows).toHaveCount(2);

  await root.locator('li[data-todo-id="0"]').getByRole("button", { name: "Delete" }).click();
  await expect(rows).toHaveCount(1);
  await expect(rows.nth(0)).toHaveAttribute("data-todo-id", "1");
  await rows.nth(0).locator('input[type="checkbox"]').check();
  await root.getByRole("button", { name: "Clear completed" }).click();
  await expect(rows).toHaveCount(0);
  await expect(status).toHaveText("0 items left");

  const instrumentation = await page.evaluate(() => globalThis.todoDispose.instrumentation());
  // ADR-0105 moved the last of these by six: this run mounts six row branches
  // and each now writes one more attribute, the declaration that the program
  // and not the browser owns the control it wraps. This backend counts its own
  // mount attributes, so the claim is counted like every attribute beside it.
  expect(instrumentation.slice(0, 7)).toEqual([0, 17, 26, 0, 0, 39, 209]);
  const regions = await page.evaluate(() => globalThis.todoDispose.regionInstrumentation());
  expect(regions).toEqual([[4, 15, 5, 4], [3, 39, 0]]);
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);

  const disposal = await page.evaluate(() => {
    globalThis.todoObserver.disconnect();
    const detachedFilter = document.querySelector('[aria-label="Todo filters"] button');
    const before = globalThis.todoDispose.instrumentation();
    globalThis.todoDispose();
    globalThis.todoDispose();
    detachedFilter.click();
    return { before, after: globalThis.todoDispose.instrumentation() };
  });
  expect(disposal.after).toEqual(disposal.before);
  await expect(root).toHaveCount(0);
});

test("scopes delegated keyboard edits and preserves retained drafts", async ({ page }) => {
  await page.goto(origin);
  await page.evaluate(async () => {
    const { mount } = await import("/TodoMVC.mjs");
    globalThis.todoDispose = mount(document.getElementById("app"));
  });
  const root = page.locator(".leanrx-todo");
  const input = root.getByRole("textbox", { name: "New todo" });
  const rows = root.locator("li");
  await input.fill("Completed");
  await root.getByRole("button", { name: "Add" }).click();
  await input.fill("Active");
  await root.getByRole("button", { name: "Add" }).click();
  const completed = rows.nth(0).getByRole("checkbox", { name: "Completed" });
  await completed.evaluate((node) => node.dispatchEvent(new Event("change", { bubbles: true })));
  await expect(completed).toBeChecked();
  await completed.evaluate((node) => node.dispatchEvent(new Event("change", { bubbles: true })));
  await expect(completed).not.toBeChecked();
  await completed.check();

  await rows.nth(1).getByRole("button", { name: "Edit" }).press("Enter");
  await expect(rows).toHaveCount(2);
  const edit = rows.nth(1).getByRole("textbox", { name: "Edit todo" });
  await edit.focus();
  await edit.fill("Unsaved draft");
  await root.getByRole("button", { name: "Clear completed" }).click();
  await expect(rows).toHaveCount(1);
  await expect(rows.nth(0)).toHaveAttribute("data-todo-id", "1");
  await expect(rows.nth(0).getByRole("textbox", { name: "Edit todo" }))
    .toHaveValue("Unsaved draft");
  await rows.nth(0).getByRole("textbox", { name: "Edit todo" }).press("Escape");
  await expect(rows.nth(0).locator("span")).toHaveText("Active");
  await page.evaluate(() => globalThis.todoDispose());
});

test("the owned count follows every row and every branch (ADR-0105)", async ({ page }) => {
  await page.goto(origin);
  await page.evaluate(async () => {
    const { mount } = await import("/TodoMVC.mjs");
    globalThis.todoOwnedDispose = mount(document.getElementById("app"));
  });
  const root = page.locator(".leanrx-todo");
  const newInput = root.locator('input[aria-label="New todo"]');
  const rows = root.locator("li");
  const owned = () => page.evaluate(() =>
    document.querySelectorAll('[autocomplete="off"]').length);
  // The static new-todo field is the only owned control before a row exists:
  // the add handler clears its value from the program's side.
  expect(await owned()).toBe(1);
  await newInput.fill("First");
  await newInput.press("Enter");
  await newInput.fill("Second");
  await newInput.press("Enter");
  await expect(rows).toHaveCount(2);
  // Each view-branch row adds its checkbox, whose `checked` the row update
  // rewrites from the item on every toggle.
  expect(await owned()).toBe(3);
  await expect(rows.locator('input[type="checkbox"][autocomplete="off"]')).toHaveCount(2);
  // The edit branch swaps the checkbox for the value-reflected editor, so the
  // count stays put while the element behind it changes.
  await rows.nth(0).getByRole("button", { name: "Edit" }).click();
  expect(await owned()).toBe(3);
  await expect(rows.nth(0).locator('input[aria-label="Edit todo"][autocomplete="off"]'))
    .toHaveCount(1);
  await expect(rows.locator('input[type="checkbox"][autocomplete="off"]')).toHaveCount(1);
  // The Edit/Delete buttons are written by nothing and declare nothing.
  await expect(root.locator('button[autocomplete="off"]')).toHaveCount(0);
  await rows.nth(0).getByRole("button", { name: "Save" }).click();
  expect(await owned()).toBe(3);
  await rows.nth(1).getByRole("button", { name: "Delete" }).click();
  await expect(rows).toHaveCount(1);
  expect(await owned()).toBe(2);
  await page.evaluate(() => globalThis.todoOwnedDispose());
  expect(await owned()).toBe(0);
});
