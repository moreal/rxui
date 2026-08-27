import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_TOGGLE_DIST;
if (!directory) throw new Error("LEANRX_TOGGLE_DIST is required");

const files = new Set([
  "ToggleLab.mjs",
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
        response.end("<!doctype html><html lang=\"en\"><head><title>Toggle Lab</title></head><body><div id=\"app\"></div></body></html>");
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

async function mountToggle(page) {
  await page.goto(origin);
  await page.evaluate(async () => {
    const { mount } = await import("/ToggleLab.mjs");
    globalThis.toggleDispose = mount(document.getElementById("app"));
  });
}

function regionMetrics(page) {
  return page.evaluate(() => globalThis.toggleDispose.regionInstrumentation()[0]);
}

test("rows mount unchecked in the view branch", async ({ page }) => {
  await mountToggle(page);
  await page.getByRole("button", { name: "Add item" }).click();
  await page.getByRole("button", { name: "Add item" }).click();
  await expect(page.locator("#toggle-text")).toHaveText("Items added: 2");
  await expect(page.locator("#items > li .item-label")).toHaveText(["Item 0", "Item 1"]);
  await expect(page.getByRole("checkbox", { name: "Toggle item" })).toHaveCount(2);
  for (const box of await page.getByRole("checkbox", { name: "Toggle item" }).all()) {
    await expect(box).not.toBeChecked();
  }
  await expect(page.locator("#items > li").first()).toHaveClass("item-row");
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("the checkbox toggles the row's done field through the delegated change payload (ADR-0049)", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await page.evaluate(() => {
    globalThis.firstRow = document.querySelector("#items > li");
  });
  const before = await regionMetrics(page);
  const first = page.locator("#items > li").nth(0);
  await first.getByRole("checkbox", { name: "Toggle item" }).check();
  // The delegated checked boolean lowers to the "true" payload, the row's
  // done field takes it, and the class selection follows through one
  // retained-row update — the checkbox stays checked (the equal-value
  // reflection is a no-op on the originating checkbox).
  await expect(first).toHaveClass("item-row done");
  await expect(first.getByRole("checkbox", { name: "Toggle item" })).toBeChecked();
  await expect(page.locator("#items > li").nth(1)).toHaveClass("item-row");
  const retained = await page.evaluate(() =>
    globalThis.firstRow === document.querySelector("#items > li"),
  );
  expect(retained).toBe(true);
  const after = await regionMetrics(page);
  // [mounts, updates, moves, disposals]: the toggle is exactly one
  // retained-row update — never a row mount, move, or disposal.
  expect(after[0]).toBe(before[0]);
  expect(after[1]).toBe(before[1] + 1);
  expect(after[2]).toBe(before[2]);
  expect(after[3]).toBe(before[3]);
  // Unchecking delegates the "false" payload and reverts the class.
  await first.getByRole("checkbox", { name: "Toggle item" }).uncheck();
  await expect(first).toHaveClass("item-row");
  await expect(first.getByRole("checkbox", { name: "Toggle item" })).not.toBeChecked();
});

test("double-clicking the label enters the edit branch and focuses the editor (ADR-0049)", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await page.evaluate(() => {
    globalThis.firstRow = document.querySelector("#items > li");
  });
  const before = await regionMetrics(page);
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  const editor = page.locator("#items > li").nth(0).getByRole("textbox", { name: "Item editor" });
  // The payload-less dblclick kind dispatches the edit action from the
  // non-button label; the branch replacement mounts the editor with the
  // mirrored draft reflected and the ADR-0048 focus transfer lands on it.
  await expect(editor).toHaveValue("Item 0");
  await expect(editor).toBeFocused();
  await expect(page.locator("#items > li").nth(0).locator(".item-label")).toHaveCount(0);
  await expect(page.locator("#items > li").nth(1).locator(".item-label")).toHaveText("Item 1");
  const retained = await page.evaluate(() =>
    globalThis.firstRow === document.querySelector("#items > li"),
  );
  expect(retained).toBe(true);
  const after = await regionMetrics(page);
  expect(after[0]).toBe(before[0]);
  expect(after[1]).toBe(before[1] + 1);
  expect(after[2]).toBe(before[2]);
  expect(after[3]).toBe(before[3]);
});

test("dblclick edit, retype, and commit round-trip with the typed text", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  const editor = page.locator("#items > li").nth(0).getByRole("textbox", { name: "Item editor" });
  await editor.fill("Renamed item");
  await page.locator("#items > li").nth(0).getByRole("button", { name: "Commit item" }).click();
  await expect(page.locator("#items > li .item-label")).toHaveText([
    "Renamed item", "Item 1",
  ]);
  await expect(page.locator("#items > li").nth(0).getByRole("textbox")).toHaveCount(0);
});

test("a dblclick inside the editor cannot clobber the draft (cross-branch agreement)", async ({ page }) => {
  await mountToggle(page);
  await page.getByRole("button", { name: "Add item" }).click();
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  const editor = page.locator("#items > li").nth(0).getByRole("textbox", { name: "Item editor" });
  await editor.fill("Draft in flight");
  // The dblclick kind takes click's exact agreement rule, so the editor
  // binds the same edit action; because edit writes only mode and retype
  // keeps draft synced with the DOM, the re-dispatch is an update no-op
  // and the equal-value reflection preserves the draft.
  await editor.dblclick();
  await expect(editor).toHaveValue("Draft in flight");
  await expect(page.locator("#items > li").nth(0)
    .getByRole("textbox", { name: "Item editor" })).toHaveCount(1);
  await page.locator("#items > li").nth(0).getByRole("button", { name: "Commit item" }).click();
  await expect(page.locator("#items > li .item-label")).toHaveText(["Draft in flight"]);
});

test("the toggle state survives an edit round-trip on the same retained row", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  const first = page.locator("#items > li").nth(0);
  await first.getByRole("checkbox", { name: "Toggle item" }).check();
  await expect(first).toHaveClass("item-row done");
  await page.evaluate(() => {
    globalThis.firstRow = document.querySelector("#items > li");
  });
  await first.locator(".item-label").dblclick();
  // Entering the edit branch re-runs the update sweep: the checked
  // reflection re-writes the done state instead of losing it.
  await expect(first.getByRole("checkbox", { name: "Toggle item" })).toBeChecked();
  await expect(first).toHaveClass("item-row done");
  const editor = first.getByRole("textbox", { name: "Item editor" });
  await editor.fill("Done and renamed");
  await first.getByRole("button", { name: "Commit item" }).click();
  await expect(first.locator(".item-label")).toHaveText("Done and renamed");
  await expect(first).toHaveClass("item-row done");
  await expect(first.getByRole("checkbox", { name: "Toggle item" })).toBeChecked();
  const retained = await page.evaluate(() =>
    globalThis.firstRow === document.querySelector("#items > li"),
  );
  expect(retained).toBe(true);
});

test("appending rows leaves earlier toggles in place and mounts fresh rows unchecked", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await page.locator("#items > li").nth(0).getByRole("checkbox", { name: "Toggle item" }).check();
  await add.click();
  await expect(page.locator("#items > li")).toHaveCount(2);
  await expect(page.locator("#items > li").nth(0)).toHaveClass("item-row done");
  await expect(page.locator("#items > li").nth(0)
    .getByRole("checkbox", { name: "Toggle item" })).toBeChecked();
  await expect(page.locator("#items > li").nth(1)).toHaveClass("item-row");
  await expect(page.locator("#items > li").nth(1)
    .getByRole("checkbox", { name: "Toggle item" })).not.toBeChecked();
  // Appending keeps focus where the user left it (ADR-0048: row mount never
  // focuses), and removal drops the toggled row without touching the other.
  await expect(add).toBeFocused();
  await page.locator("#items > li").nth(0).getByRole("button", { name: "Remove item" }).click();
  await expect(page.locator("#items > li")).toHaveCount(1);
  await expect(page.locator("#items > li").nth(0)).toHaveClass("item-row");
});

test("the sealed counts track appends and per-row toggles (ADR-0050)", async ({ page }) => {
  await mountToggle(page);
  // Both count forms mount at "0": regions mount empty by construction.
  await expect(page.locator("#items-left")).toHaveText("0 left of 0");
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await add.click();
  await expect(page.locator("#items-left strong")).toHaveText("3");
  await expect(page.locator("#items-left")).toHaveText("3 left of 3");
  // A single delegated toggle drains through updateAt (pending, not dirty);
  // the count sweep still sees the touched region and recomputes both forms.
  await page.locator("#items > li").nth(1).getByRole("checkbox", { name: "Toggle item" }).check();
  await expect(page.locator("#items-left")).toHaveText("2 left of 3");
  await page.locator("#items > li").nth(1).getByRole("checkbox", { name: "Toggle item" }).uncheck();
  await expect(page.locator("#items-left")).toHaveText("3 left of 3");
  // Removing a row updates both the predicate count and the total.
  await page.locator("#items > li").nth(0).getByRole("button", { name: "Remove item" }).click();
  await expect(page.locator("#items-left")).toHaveText("2 left of 2");
});

test("completing all broadcasts the sealed row expression with row identity preserved (ADR-0050)", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await add.click();
  await page.locator("#items > li").nth(0).getByRole("checkbox", { name: "Toggle item" }).check();
  await page.evaluate(() => {
    globalThis.firstRow = document.querySelector("#items > li");
  });
  const before = await regionMetrics(page);
  await page.getByRole("button", { name: "Complete all" }).click();
  // Every row's done field takes the broadcast "true": checkbox and class
  // selection follow through the dirty reconcile's retained-row updates.
  for (const row of await page.locator("#items > li").all()) {
    await expect(row).toHaveClass("item-row done");
    await expect(row.getByRole("checkbox", { name: "Toggle item" })).toBeChecked();
  }
  await expect(page.locator("#items-left")).toHaveText("0 left of 3");
  const retained = await page.evaluate(() =>
    globalThis.firstRow === document.querySelector("#items > li"),
  );
  expect(retained).toBe(true);
  const after = await regionMetrics(page);
  // [mounts, updates, moves, disposals]: the broadcast is exactly one
  // retained-row update per row — never a mount, move, or disposal.
  expect(after[0]).toBe(before[0]);
  expect(after[1]).toBe(before[1] + 3);
  expect(after[2]).toBe(before[2]);
  expect(after[3]).toBe(before[3]);
});

test("clearing completed disposes exactly the done rows (ADR-0050)", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await add.click();
  await page.locator("#items > li").nth(0).getByRole("checkbox", { name: "Toggle item" }).check();
  await page.locator("#items > li").nth(2).getByRole("checkbox", { name: "Toggle item" }).check();
  await page.evaluate(() => {
    globalThis.middleRow = document.querySelectorAll("#items > li")[1];
  });
  const before = await regionMetrics(page);
  await page.getByRole("button", { name: "Clear completed" }).click();
  // The predicate removal keeps exactly the rows whose done field differs
  // from the literal; the survivor keeps its DOM node.
  await expect(page.locator("#items > li")).toHaveCount(1);
  await expect(page.locator("#items > li .item-label")).toHaveText(["Item 1"]);
  await expect(page.locator("#items-left")).toHaveText("1 left of 1");
  const retained = await page.evaluate(() =>
    globalThis.middleRow === document.querySelector("#items > li"),
  );
  expect(retained).toBe(true);
  const after = await regionMetrics(page);
  expect(after[0]).toBe(before[0]);
  expect(after[1]).toBe(before[1] + 1);
  expect(after[2]).toBe(before[2]);
  expect(after[3]).toBe(before[3] + 2);
  // Clearing again is an observable no-op: nothing matches the predicate.
  await page.getByRole("button", { name: "Clear completed" }).click();
  await expect(page.locator("#items > li")).toHaveCount(1);
  await expect(page.locator("#items-left")).toHaveText("1 left of 1");
});

test("dblclick outside the label cell dispatches nothing", async ({ page }) => {
  await mountToggle(page);
  await page.getByRole("button", { name: "Add item" }).click();
  // The dblclick action array carries the edit action only at the branch
  // cell index: double-clicking the commit cell leaves the view branch.
  await page.locator("#items > li").nth(0).getByRole("button", { name: "Commit item" }).dblclick();
  await expect(page.locator("#items > li").nth(0).getByRole("textbox")).toHaveCount(0);
  await expect(page.locator("#items > li .item-label")).toHaveText(["Item 0"]);
});

test("the filter view hides exactly the non-matching rows with identity and metrics untouched (ADR-0051)", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await add.click();
  await page.locator("#items > li").nth(0).getByRole("checkbox", { name: "Toggle item" }).check();
  await page.evaluate(() => {
    globalThis.firstRow = document.querySelector("#items > li");
  });
  const before = await regionMetrics(page);
  await page.getByRole("button", { name: "Show active" }).click();
  // The filter sweep writes each row root's hidden property only: every row
  // keeps its DOM node and the region metrics do not move at all — no
  // mounts, updates, moves, or disposals.
  await expect(page.locator("#items > li")).toHaveCount(3);
  await expect(page.locator("#items > li").nth(0)).toBeHidden();
  await expect(page.locator("#items > li").nth(1)).toBeVisible();
  await expect(page.locator("#items > li").nth(2)).toBeVisible();
  // items-left counts the full row table: the displayed set follows the
  // filter while the counts stay filter-independent (ADR-0050/0051).
  await expect(page.locator("#items-left")).toHaveText("2 left of 3");
  expect(await regionMetrics(page)).toEqual(before);
  const retained = await page.evaluate(() =>
    globalThis.firstRow === document.querySelector("#items > li"),
  );
  expect(retained).toBe(true);
  // Show completed flips the displayed set; Show all reveals every retained
  // row again — the same nodes throughout.
  await page.getByRole("button", { name: "Show completed" }).click();
  await expect(page.locator("#items > li").nth(0)).toBeVisible();
  await expect(page.locator("#items > li").nth(1)).toBeHidden();
  await expect(page.locator("#items > li").nth(2)).toBeHidden();
  await page.getByRole("button", { name: "Show all" }).click();
  for (const row of await page.locator("#items > li").all()) {
    await expect(row).toBeVisible();
  }
  expect(await regionMetrics(page)).toEqual(before);
  const stillRetained = await page.evaluate(() =>
    globalThis.firstRow === document.querySelector("#items > li"),
  );
  expect(stillRetained).toBe(true);
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("a row update that changes the predicated field re-applies the filter live (ADR-0051)", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await page.getByRole("button", { name: "Show active" }).click();
  await expect(page.locator("#items > li").nth(0)).toBeVisible();
  await expect(page.locator("#items > li").nth(1)).toBeVisible();
  // The delegated toggle drains through updateAt (pending, not dirty); the
  // filter sweep still sees the touched region and hides the row that just
  // left the active set.
  await page.locator("#items > li").nth(1).getByRole("checkbox", { name: "Toggle item" }).check();
  await expect(page.locator("#items > li").nth(1)).toBeHidden();
  await expect(page.locator("#items > li").nth(0)).toBeVisible();
  await expect(page.locator("#items-left")).toHaveText("1 left of 2");
  // Under the completed filter the same row is the visible one; unchecking
  // it hides it again from the completed set.
  await page.getByRole("button", { name: "Show completed" }).click();
  await expect(page.locator("#items > li").nth(1)).toBeVisible();
  await expect(page.locator("#items > li").nth(0)).toBeHidden();
  await page.locator("#items > li").nth(1).getByRole("checkbox", { name: "Toggle item" }).uncheck();
  await expect(page.locator("#items > li").nth(1)).toBeHidden();
  await expect(page.locator("#items-left")).toHaveText("2 left of 2");
});

test("appended rows take their visibility inside the appending commit (ADR-0051)", async ({ page }) => {
  await mountToggle(page);
  await page.getByRole("button", { name: "Show completed" }).click();
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  // The append raises the touched flag, so the fresh row mounts and is
  // hidden by the same commit's filter sweep — it never flashes visible.
  await expect(page.locator("#items > li")).toHaveCount(1);
  await expect(page.locator("#items > li").nth(0)).toBeHidden();
  await expect(page.locator("#items-left")).toHaveText("1 left of 1");
  // The broadcast moves every row into the completed set: the dirty
  // reconcile and the filter sweep compose in one transaction.
  await page.getByRole("button", { name: "Complete all" }).click();
  await expect(page.locator("#items > li").nth(0)).toBeVisible();
  await expect(page.locator("#items-left")).toHaveText("0 left of 1");
});

test("broadcasts and removals compose with an active filter (ADR-0051)", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await add.click();
  await page.locator("#items > li").nth(0).getByRole("checkbox", { name: "Toggle item" }).check();
  await page.getByRole("button", { name: "Show active" }).click();
  await page.getByRole("button", { name: "Complete all" }).click();
  // Every row left the active set: all hidden, none disposed.
  await expect(page.locator("#items > li")).toHaveCount(3);
  for (const row of await page.locator("#items > li").all()) {
    await expect(row).toBeHidden();
  }
  await expect(page.locator("#items-left")).toHaveText("0 left of 3");
  await page.getByRole("button", { name: "Show completed" }).click();
  for (const row of await page.locator("#items > li").all()) {
    await expect(row).toBeVisible();
  }
  // The predicate removal disposes the done rows for real; the filter has
  // nothing left to hide.
  await page.getByRole("button", { name: "Clear completed" }).click();
  await expect(page.locator("#items > li")).toHaveCount(0);
  await expect(page.locator("#items-left")).toHaveText("0 left of 0");
});

test("Enter commits the draft through the key-branched row event (ADR-0052)", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await page.evaluate(() => {
    globalThis.firstRow = document.querySelector("#items > li");
  });
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  const editor = page.locator("#items > li").nth(0).getByRole("textbox", { name: "Item editor" });
  await editor.fill("Committed by Enter");
  const before = await regionMetrics(page);
  // The keydown dispatch matches the "Enter" arm: label takes the draft and
  // the mode flips to view in one retained-row update — exactly what the OK
  // button does, now keyboard-first.
  await editor.press("Enter");
  await expect(page.locator("#items > li .item-label")).toHaveText([
    "Committed by Enter", "Item 1",
  ]);
  await expect(page.locator("#items > li").nth(0).getByRole("textbox")).toHaveCount(0);
  const retained = await page.evaluate(() =>
    globalThis.firstRow === document.querySelector("#items > li"),
  );
  expect(retained).toBe(true);
  const after = await regionMetrics(page);
  // [mounts, updates, moves, disposals]: the commit is exactly one
  // retained-row update — never a row mount, move, or disposal.
  expect(after[0]).toBe(before[0]);
  expect(after[1]).toBe(before[1] + 1);
  expect(after[2]).toBe(before[2]);
  expect(after[3]).toBe(before[3]);
});

test("Escape reverts the draft to the pre-edit label (ADR-0052)", async ({ page }) => {
  await mountToggle(page);
  await page.getByRole("button", { name: "Add item" }).click();
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  const editor = page.locator("#items > li").nth(0).getByRole("textbox", { name: "Item editor" });
  await editor.fill("Discarded draft");
  // The "Escape" arm writes draft := label — the pre-edit value, since
  // label changes only on commit — and leaves the edit branch: the retype
  // writes are discarded and the label shows the original text.
  await editor.press("Escape");
  await expect(page.locator("#items > li .item-label")).toHaveText(["Item 0"]);
  await expect(page.locator("#items > li").nth(0).getByRole("textbox")).toHaveCount(0);
  // The next edit entry reflects the restored draft through the ADR-0047
  // value reflection — the discarded text is gone for good.
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  await expect(page.locator("#items > li").nth(0)
    .getByRole("textbox", { name: "Item editor" })).toHaveValue("Item 0");
  // Committing after the revert round-trips the restored draft.
  await page.locator("#items > li").nth(0).getByRole("button", { name: "Commit item" }).click();
  await expect(page.locator("#items > li .item-label")).toHaveText(["Item 0"]);
});

test("a key outside the sealed set is a no-op (ADR-0052)", async ({ page }) => {
  await mountToggle(page);
  await page.getByRole("button", { name: "Add item" }).click();
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  const editor = page.locator("#items > li").nth(0).getByRole("textbox", { name: "Item editor" });
  await editor.fill("Draft in flight");
  const before = await regionMetrics(page);
  // A non-matching key dispatches (the keydown listener is structural) but
  // matches no arm: no row scan, no field write, no updateAt — the editor
  // keeps its branch, value, caret ownership, and focus, and the region
  // metrics do not move at all.
  await editor.press("ArrowLeft");
  await editor.press("Shift");
  await expect(editor).toHaveValue("Draft in flight");
  await expect(editor).toBeFocused();
  expect(await regionMetrics(page)).toEqual(before);
  // The sealed set still works afterwards: Enter commits the same draft.
  await editor.press("Enter");
  await expect(page.locator("#items > li .item-label")).toHaveText(["Draft in flight"]);
});

test("Enter on an empty draft removes the row through the remove-if guard (ADR-0053)", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await page.evaluate(() => {
    globalThis.secondRow = document.querySelectorAll("#items > li")[1];
  });
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  const editor = page.locator("#items > li").nth(0).getByRole("textbox", { name: "Item editor" });
  await editor.fill("");
  const before = await regionMetrics(page);
  // The guard equality runs against the row the key scan resolved: the
  // empty draft hits `draft == ""`, so the Enter arm removes the row —
  // TodoMVC's destroy-on-empty-commit — through the same kept-filter and
  // dirty reconcile the ✕ button uses.
  await editor.press("Enter");
  await expect(page.locator("#items > li")).toHaveCount(1);
  await expect(page.locator("#items > li .item-label")).toHaveText(["Item 1"]);
  await expect(page.locator("#items-left")).toHaveText("1 left of 1");
  // The survivor keeps its DOM node — row identity preserved through the
  // disposal of its sibling.
  const retained = await page.evaluate(() =>
    globalThis.secondRow === document.querySelector("#items > li"),
  );
  expect(retained).toBe(true);
  const after = await regionMetrics(page);
  // [mounts, updates, moves, disposals]: the guard hit queues no updateAt of
  // its own — the removal rides the same dirty reconcile as the ✕ button,
  // which disposes the dispatching row and re-renders the one retained
  // survivor. Never a mount, never a move.
  expect(after[0]).toBe(before[0]);
  expect(after[1]).toBe(before[1] + 1);
  expect(after[2]).toBe(before[2]);
  expect(after[3]).toBe(before[3] + 1);
});

test("OK on an empty draft removes the row through the guarded commit (ADR-0053)", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  const editor = page.locator("#items > li").nth(0).getByRole("textbox", { name: "Item editor" });
  await editor.fill("");
  // The OK button's commit event carries the same remove-if guard, so both
  // commit paths agree on destroy-on-empty-commit.
  await page.locator("#items > li").nth(0).getByRole("button", { name: "Commit item" }).click();
  await expect(page.locator("#items > li")).toHaveCount(1);
  await expect(page.locator("#items > li .item-label")).toHaveText(["Item 1"]);
  // A nonempty draft still takes the ordinary commit path afterwards.
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  await page.locator("#items > li").nth(0)
    .getByRole("textbox", { name: "Item editor" }).fill("Kept");
  await page.locator("#items > li").nth(0).getByRole("button", { name: "Commit item" }).click();
  await expect(page.locator("#items > li .item-label")).toHaveText(["Kept"]);
});

test("Escape on an empty draft keeps the row — the revert arm is unguarded (ADR-0053)", async ({ page }) => {
  await mountToggle(page);
  await page.getByRole("button", { name: "Add item" }).click();
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  const editor = page.locator("#items > li").nth(0).getByRole("textbox", { name: "Item editor" });
  await editor.fill("");
  // Escape stays unguarded: reverting an empty draft restores the label
  // instead of destroying the row.
  await editor.press("Escape");
  await expect(page.locator("#items > li")).toHaveCount(1);
  await expect(page.locator("#items > li .item-label")).toHaveText(["Item 0"]);
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  await expect(page.locator("#items > li").nth(0)
    .getByRole("textbox", { name: "Item editor" })).toHaveValue("Item 0");
});

test("disposal removes the region, listeners, and rows idempotently", async ({ page }) => {
  await mountToggle(page);
  await page.getByRole("button", { name: "Add item" }).click();
  await expect(page.locator("#items > li")).toHaveCount(1);
  await page.evaluate(() => {
    globalThis.addButton = document.querySelector(".toggle-lab button");
    globalThis.toggleDispose();
    globalThis.toggleDispose();
  });
  await expect(page.locator(".toggle-lab")).toHaveCount(0);
  await expect(page.locator("#items")).toHaveCount(0);
  const stillAttached = await page.evaluate(() => {
    globalThis.addButton.dispatchEvent(new Event("click", { bubbles: true }));
    return document.contains(globalThis.addButton);
  });
  expect(stillAttached).toBe(false);
});
