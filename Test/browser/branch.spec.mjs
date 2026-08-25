import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_BRANCH_DIST;
if (!directory) throw new Error("LEANRX_BRANCH_DIST is required");

const files = new Set([
  "BranchLab.mjs",
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
        response.end("<!doctype html><html lang=\"en\"><head><title>Branch Lab</title></head><body><div id=\"app\"></div></body></html>");
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

async function mountBranch(page) {
  await page.goto(origin);
  await page.evaluate(async () => {
    const { mount } = await import("/BranchLab.mjs");
    globalThis.branchDispose = mount(document.getElementById("app"));
  });
}

function regionMetrics(page) {
  return page.evaluate(() => globalThis.branchDispose.regionInstrumentation()[0]);
}

test("rows mount in the view branch with no edit input in the tree", async ({ page }) => {
  await mountBranch(page);
  await page.getByRole("button", { name: "Add task" }).click();
  await page.getByRole("button", { name: "Add task" }).click();
  await expect(page.locator("#branch-text")).toHaveText("Tasks added: 2");
  await expect(page.locator("#tasks > li .task-label")).toHaveText(["Task 0", "Task 1"]);
  // ADR-0047 rejects always-mounted hidden branches: the absent edit input
  // does not exist in the DOM or the accessibility tree.
  await expect(page.locator("#tasks input")).toHaveCount(0);
  await expect(page.locator("#tasks > li").first()).toHaveClass("task-row");
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("entering the edit branch replaces the cell subtree inside a retained row", async ({ page }) => {
  await mountBranch(page);
  const add = page.getByRole("button", { name: "Add task" });
  await add.click();
  await add.click();
  const before = await regionMetrics(page);
  await page.evaluate(() => {
    globalThis.firstRow = document.querySelector("#tasks > li");
  });
  await page.locator("#tasks > li").nth(0).getByRole("button", { name: "Edit task" }).click();
  const editor = page.locator("#tasks > li").nth(0).getByRole("textbox", { name: "Task editor" });
  // The edit branch mounts with the draft (copied from the label) reflected
  // into the input's value property; the label span is gone, not hidden.
  await expect(editor).toHaveValue("Task 0");
  await expect(page.locator("#tasks > li").nth(0).locator(".task-label")).toHaveCount(0);
  await expect(page.locator("#tasks > li").nth(0)).toHaveClass("task-row editing");
  await expect(page.locator("#tasks > li").nth(1) .locator(".task-label")).toHaveText("Task 1");
  const retained = await page.evaluate(() =>
    globalThis.firstRow === document.querySelector("#tasks > li"),
  );
  expect(retained).toBe(true);
  const after = await regionMetrics(page);
  // [mounts, updates, moves, disposals]: the branch change is exactly one
  // retained-row update — never a row mount, move, or disposal.
  expect(after[0]).toBe(before[0]);
  expect(after[1]).toBe(before[1] + 1);
  expect(after[2]).toBe(before[2]);
  expect(after[3]).toBe(before[3]);
});

test("edit entry focuses the fresh input with the reflected draft (ADR-0048)", async ({ page }) => {
  await mountBranch(page);
  const add = page.getByRole("button", { name: "Add task" });
  await add.click();
  await add.click();
  await page.locator("#tasks > li").nth(0).getByRole("button", { name: "Edit task" }).click();
  const editor = page.locator("#tasks > li").nth(0).getByRole("textbox", { name: "Task editor" });
  // The replacement arm calls the ABI 16 focus export on the autoFocus-marked
  // input, so a keyboard-first user types without tabbing or clicking into it.
  await expect(editor).toBeFocused();
  await expect(editor).toHaveValue("Task 0");
  await page.keyboard.press("End");
  await page.keyboard.type("!");
  await expect(editor).toHaveValue("Task 0!");
  await page.locator("#tasks > li").nth(0).getByRole("button", { name: "Commit task" }).click();
  await expect(page.locator("#tasks > li .task-label")).toHaveText(["Task 0!", "Task 1"]);
});

test("row mount, commit, and reorder never steal focus (ADR-0048)", async ({ page }) => {
  await mountBranch(page);
  const add = page.getByRole("button", { name: "Add task" });
  await add.click();
  await add.click();
  await add.click();
  // Appending rows mounts the view branch through the row builder, which
  // never calls focus — the clicked Add button keeps it.
  await expect(add).toBeFocused();
  await page.locator("#tasks > li").nth(1).getByRole("button", { name: "Edit task" }).click();
  await expect(page.locator("#tasks > li").nth(1)
    .getByRole("textbox", { name: "Task editor" })).toBeFocused();
  // Committing replaces back to the label branch, whose subtree carries no
  // marker: the clicked OK button keeps focus.
  const commit = page.locator("#tasks > li").nth(1).getByRole("button", { name: "Commit task" });
  await commit.click();
  await expect(commit).toBeFocused();
  // A structural reconcile (removing an earlier row) retains the editing row
  // without a branch change, so the update callback never reaches focus: the
  // editor is not re-focused behind the user's back.
  await page.locator("#tasks > li").nth(2).getByRole("button", { name: "Edit task" }).click();
  await page.locator("#tasks > li").nth(0).getByRole("button", { name: "Remove task" }).click();
  const movedEditor = page.locator("#tasks > li").nth(1).getByRole("textbox", { name: "Task editor" });
  await expect(movedEditor).toHaveValue("Task 2");
  const editorFocused = await movedEditor.evaluate((node) => document.activeElement === node);
  expect(editorFocused).toBe(false);
});

test("typing drains retained-row updates and the equal-value reflection preserves the caret", async ({ page }) => {
  await mountBranch(page);
  await page.getByRole("button", { name: "Add task" }).click();
  await page.locator("#tasks > li").nth(0).getByRole("button", { name: "Edit task" }).click();
  const editor = page.locator("#tasks > li").nth(0).getByRole("textbox", { name: "Task editor" });
  await editor.fill("abcdef");
  const before = await regionMetrics(page);
  await editor.evaluate((node) => node.setSelectionRange(3, 3));
  await page.keyboard.type("X");
  await expect(editor).toHaveValue("abcXdef");
  // The retype update writes the string the input already holds back into its
  // value property; the WHATWG equal-value assignment is a caret no-op
  // (ADR-0038, reused in row scope by ADR-0047), so the caret stays mid-text.
  const caret = await editor.evaluate((node) => node.selectionStart);
  expect(caret).toBe(4);
  const after = await regionMetrics(page);
  expect(after[0]).toBe(before[0]);
  expect(after[1]).toBe(before[1] + 1);
  expect(after[3]).toBe(before[3]);
});

test("committing returns the label branch with the typed text and retained identity", async ({ page }) => {
  await mountBranch(page);
  const add = page.getByRole("button", { name: "Add task" });
  await add.click();
  await add.click();
  await page.evaluate(() => {
    globalThis.firstRow = document.querySelector("#tasks > li");
  });
  await page.locator("#tasks > li").nth(0).getByRole("button", { name: "Edit task" }).click();
  const editor = page.locator("#tasks > li").nth(0).getByRole("textbox", { name: "Task editor" });
  await editor.fill("Renamed task");
  const before = await regionMetrics(page);
  await page.locator("#tasks > li").nth(0).getByRole("button", { name: "Commit task" }).click();
  await expect(page.locator("#tasks > li .task-label")).toHaveText([
    "Renamed task", "Task 1",
  ]);
  await expect(page.locator("#tasks > li").nth(0)).toHaveClass("task-row");
  await expect(page.locator("#tasks input")).toHaveCount(0);
  const retained = await page.evaluate(() =>
    globalThis.firstRow === document.querySelector("#tasks > li"),
  );
  expect(retained).toBe(true);
  const after = await regionMetrics(page);
  expect(after[0]).toBe(before[0]);
  expect(after[1]).toBe(before[1] + 1);
  expect(after[2]).toBe(before[2]);
  expect(after[3]).toBe(before[3]);
});

test("the always-visible commit button is a no-op in the view branch", async ({ page }) => {
  await mountBranch(page);
  await page.getByRole("button", { name: "Add task" }).click();
  await page.locator("#tasks > li").nth(0).getByRole("button", { name: "Commit task" }).click();
  await expect(page.locator("#tasks > li .task-label")).toHaveText(["Task 0"]);
  await expect(page.locator("#tasks > li").nth(0)).toHaveClass("task-row");
  // Clicking the label cell itself dispatches nothing: the click action array
  // carries no action at the branch cell index.
  await page.locator("#tasks > li .task-label").first().click();
  await expect(page.locator("#tasks > li")).toHaveCount(1);
});

test("an editing row keeps its draft and branch across structural reconciles", async ({ page }) => {
  await mountBranch(page);
  const add = page.getByRole("button", { name: "Add task" });
  await add.click();
  await add.click();
  await add.click();
  await page.locator("#tasks > li").nth(1).getByRole("button", { name: "Edit task" }).click();
  const editor = page.locator("#tasks > li").nth(1).getByRole("textbox", { name: "Task editor" });
  await editor.fill("Draft in flight");
  await page.locator("#tasks > li").nth(0).getByRole("button", { name: "Remove task" }).click();
  const movedEditor = page.locator("#tasks > li").nth(0).getByRole("textbox", { name: "Task editor" });
  await expect(movedEditor).toHaveValue("Draft in flight");
  await expect(page.locator("#tasks > li").nth(0)).toHaveClass("task-row editing");
  await movedEditor.click();
  await page.locator("#tasks > li").nth(0).getByRole("button", { name: "Commit task" }).click();
  await expect(page.locator("#tasks > li .task-label")).toHaveText([
    "Draft in flight", "Task 2",
  ]);
});

test("disposal removes the region, listeners, and rows idempotently", async ({ page }) => {
  await mountBranch(page);
  await page.getByRole("button", { name: "Add task" }).click();
  await expect(page.locator("#tasks > li")).toHaveCount(1);
  await page.evaluate(() => {
    globalThis.addButton = document.querySelector(".branch-lab button");
    globalThis.branchDispose();
    globalThis.branchDispose();
  });
  await expect(page.locator(".branch-lab")).toHaveCount(0);
  await expect(page.locator("#tasks")).toHaveCount(0);
  const stillAttached = await page.evaluate(() => {
    globalThis.addButton.dispatchEvent(new Event("click", { bubbles: true }));
    return document.contains(globalThis.addButton);
  });
  expect(stillAttached).toBe(false);
});
