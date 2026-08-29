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
  "leanrx_form_events.mjs",
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
  // Both count forms mount at "0" and the ADR-0062 label at its plural
  // branch: regions mount empty by construction.
  await expect(page.locator("#items-left")).toHaveText("0 items left of 0");
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await add.click();
  await expect(page.locator("#items-left strong")).toHaveText("3");
  await expect(page.locator("#items-left")).toHaveText("3 items left of 3");
  // A single delegated toggle drains through updateAt (pending, not dirty);
  // the count sweep still sees the touched region and recomputes both forms.
  await page.locator("#items > li").nth(1).getByRole("checkbox", { name: "Toggle item" }).check();
  await expect(page.locator("#items-left")).toHaveText("2 items left of 3");
  await page.locator("#items > li").nth(1).getByRole("checkbox", { name: "Toggle item" }).uncheck();
  await expect(page.locator("#items-left")).toHaveText("3 items left of 3");
  // Removing a row updates both the predicate count and the total.
  await page.locator("#items > li").nth(0).getByRole("button", { name: "Remove item" }).click();
  await expect(page.locator("#items-left")).toHaveText("2 items left of 2");
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
  await expect(page.locator("#items-left")).toHaveText("0 items left of 3");
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
  await expect(page.locator("#items-left")).toHaveText("1 item left of 1");
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
  // The ADR-0059 affordance hides the button while no row is done, so the
  // click is dispatched structurally — the affordance is not the contract:
  // the removal stays a no-op wherever it is triggered from.
  await page.getByRole("button", { name: "Clear completed", includeHidden: true })
    .dispatchEvent("click");
  await expect(page.locator("#items > li")).toHaveCount(1);
  await expect(page.locator("#items-left")).toHaveText("1 item left of 1");
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
  await expect(page.locator("#items-left")).toHaveText("2 items left of 3");
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
  await expect(page.locator("#items-left")).toHaveText("1 item left of 2");
  // Under the completed filter the same row is the visible one; unchecking
  // it hides it again from the completed set.
  await page.getByRole("button", { name: "Show completed" }).click();
  await expect(page.locator("#items > li").nth(1)).toBeVisible();
  await expect(page.locator("#items > li").nth(0)).toBeHidden();
  await page.locator("#items > li").nth(1).getByRole("checkbox", { name: "Toggle item" }).uncheck();
  await expect(page.locator("#items > li").nth(1)).toBeHidden();
  await expect(page.locator("#items-left")).toHaveText("2 items left of 2");
});

test("appended rows take their visibility inside the appending commit (ADR-0051)", async ({ page }) => {
  await mountToggle(page);
  // The empty-list chrome hides the filter buttons with the footer, so the
  // completed filter is set through a synthetic click on the hidden button —
  // the dispatch, not the affordance, carries the contract (the ADR-0055
  // rejection 2 reasoning).
  await page.locator("button", { hasText: "Show completed" })
    .evaluate((button) => button.click());
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  // The append raises the touched flag, so the fresh row mounts and is
  // hidden by the same commit's filter sweep — it never flashes visible.
  await expect(page.locator("#items > li")).toHaveCount(1);
  await expect(page.locator("#items > li").nth(0)).toBeHidden();
  await expect(page.locator("#items-left")).toHaveText("1 item left of 1");
  // The broadcast moves every row into the completed set: the dirty
  // reconcile and the filter sweep compose in one transaction.
  await page.getByRole("button", { name: "Complete all" }).click();
  await expect(page.locator("#items > li").nth(0)).toBeVisible();
  await expect(page.locator("#items-left")).toHaveText("0 items left of 1");
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
  await expect(page.locator("#items-left")).toHaveText("0 items left of 3");
  await page.getByRole("button", { name: "Show completed" }).click();
  for (const row of await page.locator("#items > li").all()) {
    await expect(row).toBeVisible();
  }
  // The predicate removal disposes the done rows for real; the filter has
  // nothing left to hide.
  await page.getByRole("button", { name: "Clear completed" }).click();
  await expect(page.locator("#items > li")).toHaveCount(0);
  await expect(page.locator("#items-left")).toHaveText("0 items left of 0");
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
  await expect(page.locator("#items-left")).toHaveText("1 item left of 1");
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

test("Enter on a whitespace-only draft removes the row through the trimmed guard (ADR-0054)", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await page.evaluate(() => {
    globalThis.secondRow = document.querySelectorAll("#items > li")[1];
  });
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  const editor = page.locator("#items > li").nth(0).getByRole("textbox", { name: "Item editor" });
  await editor.fill("   ");
  const before = await regionMetrics(page);
  // The guard subject is the trimmed draft: `trim "   "` is the empty
  // string, so a whitespace-only commit destroys the row exactly as an
  // empty one does — TodoMVC's trim contract on the guard path.
  await editor.press("Enter");
  await expect(page.locator("#items > li")).toHaveCount(1);
  await expect(page.locator("#items > li .item-label")).toHaveText(["Item 1"]);
  await expect(page.locator("#items-left")).toHaveText("1 item left of 1");
  const retained = await page.evaluate(() =>
    globalThis.secondRow === document.querySelector("#items > li"),
  );
  expect(retained).toBe(true);
  const after = await regionMetrics(page);
  // [mounts, updates, moves, disposals]: the trimmed guard hit rides the
  // same dirty reconcile as the raw guard — one disposal, one survivor
  // update, never a mount or a move.
  expect(after[0]).toBe(before[0]);
  expect(after[1]).toBe(before[1] + 1);
  expect(after[2]).toBe(before[2]);
  expect(after[3]).toBe(before[3] + 1);
});

test("a committed label is stored trimmed and the draft re-mirrors it (ADR-0054)", async ({ page }) => {
  await mountToggle(page);
  await page.getByRole("button", { name: "Add item" }).click();
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  const editor = page.locator("#items > li").nth(0).getByRole("textbox", { name: "Item editor" });
  await editor.fill("  x  ");
  // A draft with surrounding whitespace misses the trimmed guard and
  // commits the trimmed value: `" x "`-style input stores as `"x"`.
  await editor.press("Enter");
  await expect(page.locator("#items > li .item-label")).toHaveText(["x"]);
  // The commit re-mirrors the draft to the trimmed value, so the next edit
  // entry starts from the stored label — the ADR-0047 value reflection
  // shows no leftover whitespace.
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  await expect(page.locator("#items > li").nth(0)
    .getByRole("textbox", { name: "Item editor" })).toHaveValue("x");
  // The OK button's guarded commit agrees on the trim contract.
  await page.locator("#items > li").nth(0)
    .getByRole("textbox", { name: "Item editor" }).fill("\ttabbed label\t");
  await page.locator("#items > li").nth(0).getByRole("button", { name: "Commit item" }).click();
  await expect(page.locator("#items > li .item-label")).toHaveText(["tabbed label"]);
});

test("Add on a whitespace-only draft is a whole-event no-op (ADR-0055/0057)", async ({ page }) => {
  await mountToggle(page);
  await page.getByRole("button", { name: "Add item" }).click();
  const draft = page.getByRole("textbox", { name: "New todo" });
  await draft.fill(" \t ");
  const addTodo = page.getByRole("button", { name: "Add todo" });
  // The ADR-0057 affordance grays the button on exactly the guard's trimmed
  // equality, so a real click can no longer reach the dispatch function.
  await expect(addTodo).toBeDisabled();
  const beforeTx = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  const beforeRegion = await regionMetrics(page);
  // The affordance is not the contract (ADR-0055 rejection 2): observe the
  // skip guard itself by handing the disabled button a synthetic click —
  // the listener still runs, and the dispatch function returns before the
  // transaction begins with no begin bookkeeping, no event trace, no
  // write, no append, and no region touch.
  await addTodo.evaluate((button) =>
    button.dispatchEvent(new MouseEvent("click", { bubbles: true })));
  await expect(page.locator("#items > li")).toHaveCount(1);
  await expect(page.locator("#items-left")).toHaveText("1 item left of 1");
  // The draft is not written either — the guard hit is a no-op, not a
  // reset: the controlled input keeps the whitespace text.
  await expect(draft).toHaveValue(" \t ");
  const afterTx = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  // [begins, commits, writes, …, trace, …]: the whole transaction shell was
  // skipped — counters and the trace list are exactly the pre-click values.
  expect(afterTx).toEqual(beforeTx);
  expect(await regionMetrics(page)).toEqual(beforeRegion);
});

test("Add on a valid draft appends the trimmed label and resets the draft (ADR-0055)", async ({ page }) => {
  await mountToggle(page);
  const draft = page.getByRole("textbox", { name: "New todo" });
  await draft.fill("  buy milk \t");
  const before = await regionMetrics(page);
  // The guard miss appends one row whose label (and mirrored row draft) is
  // the ASCII-trimmed component draft, and resets the draft through the
  // same transaction — the ADR-0038 controlled reflection empties the
  // input.
  await page.getByRole("button", { name: "Add todo" }).click();
  await expect(page.locator("#items > li .item-label")).toHaveText(["buy milk"]);
  await expect(page.locator("#items-left")).toHaveText("1 item left of 1");
  await expect(draft).toHaveValue("");
  const after = await regionMetrics(page);
  // [mounts, updates, moves, disposals]: the append is one row mount, and
  // the empty-region rebuild counts its one insertion before the anchor as
  // a placement — never an update or a disposal.
  expect(after[0]).toBe(before[0] + 1);
  expect(after[1]).toBe(before[1]);
  expect(after[2]).toBe(before[2] + 1);
  expect(after[3]).toBe(before[3]);
  // The appended row is a full citizen of the row vocabulary: the mirrored
  // draft enters the editor trimmed.
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  await expect(page.locator("#items > li").nth(0)
    .getByRole("textbox", { name: "Item editor" })).toHaveValue("buy milk");
});

test("Enter on a whitespace-only draft is a whole-event no-op (ADR-0056)", async ({ page }) => {
  await mountToggle(page);
  await page.getByRole("button", { name: "Add item" }).click();
  const draft = page.getByRole("textbox", { name: "New todo" });
  await draft.fill(" \t ");
  const beforeTx = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  const beforeRegion = await regionMetrics(page);
  // The Enter arm carries the same ADR-0055 skip guard the Add button's
  // dispatch evaluates: the matched arm returns before its transaction
  // begins — no begin bookkeeping, no event trace, no write, no append, no
  // region touch — exactly the button path's guard hit.
  await draft.press("Enter");
  await expect(page.locator("#items > li")).toHaveCount(1);
  await expect(page.locator("#items-left")).toHaveText("1 item left of 1");
  await expect(draft).toHaveValue(" \t ");
  const afterTx = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(afterTx).toEqual(beforeTx);
  expect(await regionMetrics(page)).toEqual(beforeRegion);
});

test("Enter on a valid draft runs the Add button's guarded add (ADR-0056)", async ({ page }) => {
  await mountToggle(page);
  const draft = page.getByRole("textbox", { name: "New todo" });
  await draft.fill("  buy milk \t");
  const before = await regionMetrics(page);
  // The Enter arm's guard miss is the Add button's transaction observable
  // for observable: one row mount with the ASCII-trimmed label, the mirrored
  // row draft, and the component draft reset through the controlled
  // reflection — traced under the arm's own event:confirmAdd:Enter label.
  await draft.press("Enter");
  await expect(page.locator("#items > li .item-label")).toHaveText(["buy milk"]);
  await expect(page.locator("#items-left")).toHaveText("1 item left of 1");
  await expect(draft).toHaveValue("");
  const after = await regionMetrics(page);
  expect(after[0]).toBe(before[0] + 1);
  expect(after[1]).toBe(before[1]);
  expect(after[2]).toBe(before[2] + 1);
  expect(after[3]).toBe(before[3]);
  const trace = await page.evaluate(() => globalThis.toggleDispose.instrumentation()[7]);
  expect(trace).toContain("event:confirmAdd:Enter");
  expect(trace).toContain("region:items:append");
  // The appended row enters the full row vocabulary: its editor opens on
  // the trimmed mirrored draft.
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  await expect(page.locator("#items > li").nth(0)
    .getByRole("textbox", { name: "Item editor" })).toHaveValue("buy milk");
});

test("a key outside the sealed arm table moves nothing (ADR-0056)", async ({ page }) => {
  await mountToggle(page);
  const draft = page.getByRole("textbox", { name: "New todo" });
  await draft.fill("buy milk");
  const beforeTx = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  const beforeRegion = await regionMetrics(page);
  // A non-matching key returns from the ADR-0056 dispatch function before
  // the context is even destructured: no transaction shell at all — cheaper
  // than the row-scope non-match, which begins and commits empty.
  await draft.press("ArrowLeft");
  await draft.press("Shift");
  await expect(page.locator("#items > li")).toHaveCount(0);
  await expect(draft).toHaveValue("buy milk");
  const afterTx = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(afterTx).toEqual(beforeTx);
  expect(await regionMetrics(page)).toEqual(beforeRegion);
});

test("the Add affordance disables exactly on a whitespace-only draft (ADR-0057)", async ({ page }) => {
  await mountToggle(page);
  const draft = page.getByRole("textbox", { name: "New todo" });
  const addTodo = page.getByRole("button", { name: "Add todo" });
  // The button mounts disabled: the draft starts empty, and mount writes the
  // trimmed equality into the disabled property before any transaction.
  await expect(addTodo).toBeDisabled();
  // Whitespace-only typing keeps the trimmed subject empty.
  await draft.fill(" \t ");
  await expect(addTodo).toBeDisabled();
  // The first non-whitespace character flips the equality, and the commit
  // sweep writes the property through setProperty.
  await draft.fill(" \t x");
  await expect(addTodo).toBeEnabled();
  // Clearing the draft re-disables through the same sweep.
  await draft.fill("");
  await expect(addTodo).toBeDisabled();
  // A valid add resets the draft inside the guarded transaction, and the
  // same commit sweep re-disables the button before the click returns.
  await draft.fill("  buy milk ");
  await expect(addTodo).toBeEnabled();
  await addTodo.click();
  await expect(page.locator("#items > li .item-label")).toHaveText(["buy milk"]);
  await expect(draft).toHaveValue("");
  await expect(addTodo).toBeDisabled();
});

test("the affordance mirrors the dispatch guard with the equal-value sweep no-op (ADR-0057)", async ({ page }) => {
  await mountToggle(page);
  const draft = page.getByRole("textbox", { name: "New todo" });
  const addTodo = page.getByRole("button", { name: "Add todo" });
  // For every draft the affordance equals the guard's trimmed emptiness —
  // the same asciiTrimPattern equality the skip guard evaluates, run by the
  // commit sweep instead of the dispatch function.
  // The NBSP draft pins the ASCII alignment: it survives the trim on both
  // the affordance and the guard, so the button stays live and Enter adds.
  for (const value of ["", " \t ", " x ", "x", " \u00a0 "]) {
    await draft.fill(value);
    if (value.replace(/^[ \t\r\n]+|[ \t\r\n]+$/g, "") === "") {
      await expect(addTodo).toBeDisabled();
    } else {
      await expect(addTodo).toBeEnabled();
    }
  }
  // Appending a trailing space to a valid draft re-evaluates the selection
  // but writes nothing: the trimmed equality is unchanged, so the compare
  // half of evaluate-compare-write swallows the write.
  await draft.fill("x");
  const evaluated = (tx) =>
    tx[7].filter((entry) => entry === "attr:0:disabled:evaluated").length;
  const written = (tx) =>
    tx[7].filter((entry) => entry === "dom:attr:0:disabled:write").length;
  const before = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  await draft.press("End");
  await draft.press(" ");
  const after = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(evaluated(after)).toBe(evaluated(before) + 1);
  expect(written(after)).toBe(written(before));
  await expect(addTodo).toBeEnabled();
  // Where the affordance disables, the Enter path still carries the
  // contract: the guard, not the grayed button, keeps the add a no-op.
  await draft.fill(" \t ");
  await expect(addTodo).toBeDisabled();
  const beforeTx = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  await draft.press("Enter");
  const afterTx = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(afterTx).toEqual(beforeTx);
  await expect(page.locator("#items > li")).toHaveCount(0);
});

test("the items wrapper mounts hidden and the first append reveals it (ADR-0058)", async ({ page }) => {
  await mountToggle(page);
  const wrapper = page.locator("#items");
  // Regions mount empty by construction (the ADR-0050 "0" reasoning), so
  // the wrapper mounts with its hidden property already true — written by
  // mount before any transaction exists.
  await expect(wrapper).toBeHidden();
  expect(await wrapper.evaluate((element) => element.hidden)).toBe(true);
  // The first append touches the region; the sweep re-evaluates the
  // row-table emptiness on the count texts' region-touch path and flips
  // the property through setProperty.
  await page.getByRole("button", { name: "Add item" }).click();
  await expect(wrapper).toBeVisible();
  expect(await wrapper.evaluate((element) => element.hidden)).toBe(false);
  const trace = await page.evaluate(() => globalThis.toggleDispose.instrumentation()[7]);
  expect(trace).toContain("attr:2:hidden:evaluated");
  expect(trace).toContain("dom:attr:2:hidden:write");
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("removing the last row hides the wrapper again (ADR-0058)", async ({ page }) => {
  await mountToggle(page);
  const wrapper = page.locator("#items");
  await page.getByRole("button", { name: "Add item" }).click();
  await expect(wrapper).toBeVisible();
  // The ✕ removal disposes the last row; the same commit's sweep sees the
  // empty row table and re-hides the wrapper.
  await page.locator("#items > li").first()
    .getByRole("button", { name: "Remove item" }).click();
  await expect(page.locator("#items > li")).toHaveCount(0);
  await expect(wrapper).toBeHidden();
  // The next append reveals it again, and draining the region through
  // completeAll + clearCompleted re-hides it — the broadcast and the
  // predicate removal ride the same region-touch path.
  await page.getByRole("button", { name: "Add item" }).click();
  await page.getByRole("button", { name: "Add item" }).click();
  await expect(wrapper).toBeVisible();
  await page.getByRole("button", { name: "Complete all" }).click();
  await expect(wrapper).toBeVisible();
  await page.getByRole("button", { name: "Clear completed" }).click();
  await expect(page.locator("#items > li")).toHaveCount(0);
  await expect(wrapper).toBeHidden();
  // The guarded empty commit (ADR-0053) removes through the same reconcile:
  // the wrapper follows the row table there too.
  await page.getByRole("button", { name: "Add item" }).click();
  await expect(wrapper).toBeVisible();
  await page.locator("#items > li").first().locator(".item-label").dblclick();
  const editor = page.locator("#items > li").first()
    .getByRole("textbox", { name: "Item editor" });
  await editor.fill("");
  await editor.press("Enter");
  await expect(page.locator("#items > li")).toHaveCount(0);
  await expect(wrapper).toBeHidden();
});

test("a filter hiding every row leaves the wrapper visible (ADR-0058)", async ({ page }) => {
  await mountToggle(page);
  const wrapper = page.locator("#items");
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await expect(wrapper).toBeVisible();
  // Every row is active, so the completed filter hides all of them — but
  // the visibility subject is the row table's total, not the displayed
  // rows: the wrapper stays revealed around an all-hidden list.
  await page.getByRole("button", { name: "Show completed" }).click();
  await expect(page.locator("#items > li:visible")).toHaveCount(0);
  // With every row filter-hidden the wrapper has no box to be "visible"
  // by, so observe the property and the computed display directly: the
  // wrapper is not hidden — the all-hidden list is a filtered view of a
  // nonempty row table, not an empty section.
  expect(await wrapper.evaluate((element) => element.hidden)).toBe(false);
  expect(await wrapper.evaluate(
    (element) => getComputedStyle(element).display)).not.toBe("none");
  await expect(page.locator("#items-left")).toHaveText("2 items left of 2");
  await page.getByRole("button", { name: "Show all" }).click();
  await expect(page.locator("#items > li:visible")).toHaveCount(2);
  // A filter change alone never touches the region, so the hidden
  // selection is not even re-evaluated by it; appending while filtered
  // keeps the wrapper revealed through the equal-value compare.
  const evaluated = (tx) =>
    tx[7].filter((entry) => entry === "attr:2:hidden:evaluated").length;
  const written = (tx) =>
    tx[7].filter((entry) => entry === "dom:attr:2:hidden:write").length;
  const before = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  await add.click();
  const after = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(evaluated(after)).toBe(evaluated(before) + 1);
  expect(written(after)).toBe(written(before));
  await expect(wrapper).toBeVisible();
});

test("the clear-completed affordance mounts hidden and the first done toggle reveals it (ADR-0059)", async ({ page }) => {
  await mountToggle(page);
  const clear = page.locator("button", { hasText: "Clear completed" });
  // An empty region satisfies no predicate: the button mounts with its
  // hidden property already true — written by mount before any transaction
  // exists, exactly like the ADR-0058 wrapper.
  await expect(clear).toBeHidden();
  expect(await clear.evaluate((element) => element.hidden)).toBe(true);
  // Appending a not-done row touches the region: the predicate scan runs
  // but counts zero done rows, so the equal-value compare swallows the
  // write and the button stays hidden.
  await page.getByRole("button", { name: "Add item" }).click();
  await expect(clear).toBeHidden();
  const evaluated = (tx) =>
    tx[7].filter((entry) => entry === "attr:1:hidden:evaluated").length;
  const written = (tx) =>
    tx[7].filter((entry) => entry === "dom:attr:1:hidden:write").length;
  const appended = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(evaluated(appended)).toBe(1);
  expect(written(appended)).toBe(0);
  // The first done toggle flips the predicate count off zero: the same
  // commit's sweep reveals the button through setProperty.
  await page.locator("#items > li").first()
    .getByRole("checkbox", { name: "Toggle item" }).check();
  await expect(clear).toBeVisible();
  const toggled = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(evaluated(toggled)).toBe(2);
  expect(written(toggled)).toBe(1);
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("draining the done rows hides the affordance again (ADR-0059)", async ({ page }) => {
  await mountToggle(page);
  const clear = page.locator("button", { hasText: "Clear completed" });
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  const firstToggle = page.locator("#items > li").first()
    .getByRole("checkbox", { name: "Toggle item" });
  // Untoggling the last done row drains the predicate count back to zero:
  // the pending row update touches the region and the sweep re-hides the
  // button — no structural change needed.
  await firstToggle.check();
  await expect(clear).toBeVisible();
  await firstToggle.uncheck();
  await expect(clear).toBeHidden();
  // clearCompleted itself removes every done row, so its own commit hides
  // the affordance that triggered it.
  await firstToggle.check();
  await expect(clear).toBeVisible();
  await clear.click();
  await expect(page.locator("#items > li")).toHaveCount(1);
  await expect(clear).toBeHidden();
  // The ✕ removal of the last done row rides the same reconcile.
  await page.locator("#items > li").first()
    .getByRole("checkbox", { name: "Toggle item" }).check();
  await expect(clear).toBeVisible();
  await page.locator("#items > li").first()
    .getByRole("button", { name: "Remove item" }).click();
  await expect(page.locator("#items > li")).toHaveCount(0);
  await expect(clear).toBeHidden();
});

test("a filter change never re-evaluates the affordance and completeAll keeps it revealed (ADR-0059)", async ({ page }) => {
  await mountToggle(page);
  const clear = page.locator("button", { hasText: "Clear completed" });
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await page.locator("#items > li").first()
    .getByRole("checkbox", { name: "Toggle item" }).check();
  await expect(clear).toBeVisible();
  // A filter change alone never touches the region, so the predicate scan
  // does not even run — the affordance follows the row table, not the
  // displayed rows, and stays revealed while the done row is filter-hidden.
  const evaluated = (tx) =>
    tx[7].filter((entry) => entry === "attr:1:hidden:evaluated").length;
  const before = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  await page.getByRole("button", { name: "Show active" }).click();
  await expect(page.locator("#items > li:visible")).toHaveCount(1);
  const filtered = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(evaluated(filtered)).toBe(evaluated(before));
  expect(await clear.evaluate((element) => element.hidden)).toBe(false);
  await page.getByRole("button", { name: "Show all" }).click();
  // The completeAll broadcast makes every row done: the region-touch sweep
  // re-counts a nonzero predicate and the button stays revealed through
  // the equal-value compare — one evaluation, no write.
  const beforeAll = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  await page.getByRole("button", { name: "Complete all" }).click();
  const afterAll = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(evaluated(afterAll)).toBe(evaluated(beforeAll) + 1);
  const written = (tx) =>
    tx[7].filter((entry) => entry === "dom:attr:1:hidden:write").length;
  expect(written(afterAll)).toBe(written(beforeAll));
  await expect(clear).toBeVisible();
});

test("the toggle-all box mounts checked and the first not-done append unchecks it (ADR-0060)", async ({ page }) => {
  await mountToggle(page);
  // The box now also mounts hidden with the empty-list chrome, so address
  // it by id — the role query excludes hidden elements.
  const box = page.locator("#toggle-all");
  // An empty region has no row failing the predicate: the box mounts with
  // its checked property already true — the vacuous all-complete truth,
  // written by mount before any transaction exists, exactly like the
  // ADR-0058/0059 hidden slots beside it.
  await expect(box).toBeChecked();
  expect(await box.evaluate((element) => element.checked)).toBe(true);
  const evaluated = (tx) =>
    tx[7].filter((entry) => entry === "attr:3:checked:evaluated").length;
  const written = (tx) =>
    tx[7].filter((entry) => entry === "dom:attr:3:checked:write").length;
  // The first not-done append flips the predicate count off zero: the same
  // region-touch sweep the hidden slots ride unchecks the box through
  // setProperty — one evaluation, one write.
  await page.getByRole("button", { name: "Add item" }).click();
  await expect(box).not.toBeChecked();
  const appended = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(evaluated(appended)).toBe(1);
  expect(written(appended)).toBe(1);
  // The completeAll broadcast drains the not-done count back to zero: the
  // box checks again through the same slot.
  await page.getByRole("button", { name: "Complete all" }).click();
  await expect(box).toBeChecked();
  const completed = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(evaluated(completed)).toBe(2);
  expect(written(completed)).toBe(2);
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("untoggling and appending uncheck the box and an emptied region restores the vacuous truth (ADR-0060)", async ({ page }) => {
  await mountToggle(page);
  // Addressed by id: clearCompleted empties the region at the end, hiding
  // the box with the empty-list chrome.
  const box = page.locator("#toggle-all");
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  const rowToggle = page.locator("#items > li").first()
    .getByRole("checkbox", { name: "Toggle item" });
  await rowToggle.check();
  await expect(box).toBeChecked();
  // Untoggling the last done row raises the not-done count off zero: the
  // pending row update touches the region and the sweep unchecks the box.
  await rowToggle.uncheck();
  await expect(box).not.toBeChecked();
  await rowToggle.check();
  await expect(box).toBeChecked();
  // Appending while all rows are done unchecks it again — rows append
  // not-done.
  await add.click();
  await expect(box).not.toBeChecked();
  // Removing the last not-done row through ✕ drains the count to zero and
  // re-checks the box through the ordinary reconcile.
  await page.locator("#items > li").nth(1)
    .getByRole("button", { name: "Remove item" }).click();
  await expect(box).toBeChecked();
  // clearCompleted emptying the region keeps the vacuous truth: the scan
  // still counts zero not-done rows, so the equal-value compare swallows
  // the write and the box stays checked — one evaluation, no write.
  const evaluated = (tx) =>
    tx[7].filter((entry) => entry === "attr:3:checked:evaluated").length;
  const written = (tx) =>
    tx[7].filter((entry) => entry === "dom:attr:3:checked:write").length;
  const before = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  await page.getByRole("button", { name: "Clear completed" }).click();
  await expect(page.locator("#items > li")).toHaveCount(0);
  await expect(box).toBeChecked();
  const cleared = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(evaluated(cleared)).toBe(evaluated(before) + 1);
  expect(written(cleared)).toBe(written(before));
});

test("a filter change never re-evaluates the box and its change broadcasts the payload both ways (ADR-0061)", async ({ page }) => {
  await mountToggle(page);
  const box = page.getByRole("checkbox", { name: "Toggle all" });
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await expect(box).not.toBeChecked();
  // A filter change alone never touches the region, so the checked scan
  // does not even run — the box follows the row table, not the displayed
  // rows, and stays unchecked while every not-done row is filter-hidden
  // (ADR-0051 non-touch preserved across the rebinding).
  const evaluated = (tx) =>
    tx[7].filter((entry) => entry === "attr:3:checked:evaluated").length;
  const before = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  await page.getByRole("button", { name: "Show completed" }).click();
  await expect(page.locator("#items > li:visible")).toHaveCount(0);
  const filtered = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(evaluated(filtered)).toBe(evaluated(before));
  expect(await box.evaluate((element) => element.checked)).toBe(false);
  await page.getByRole("button", { name: "Show all" }).click();
  // Checking the box fires the toggleAll payload broadcast with the "true"
  // payload: every row's done takes it, every row checkbox follows through
  // its ADR-0049 reflection, and the sweep's cache flip re-writes the
  // property the click already set.
  await box.check();
  await expect(box).toBeChecked();
  await expect(page.locator("#items > li")
    .getByRole("checkbox", { name: "Toggle item", checked: true })).toHaveCount(2);
  await expect(page.locator("#items-left")).toHaveText("0 items left of 2");
  // The uncheck path is closed (ADR-0061, replacing the ADR-0060 cache-DOM
  // divergence): unchecking the box broadcasts the "false" payload, every
  // row reverts to not-done, and the sweep's evaluate-compare-write agrees
  // with the browser's own uncheck — cache and DOM both false, no
  // divergence left to pin.
  const beforeUncheck = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  await box.uncheck();
  const afterUncheck = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(evaluated(afterUncheck)).toBe(evaluated(beforeUncheck) + 1);
  expect(await box.evaluate((element) => element.checked)).toBe(false);
  await expect(box).not.toBeChecked();
  await expect(page.locator("#items > li")
    .getByRole("checkbox", { name: "Toggle item", checked: true })).toHaveCount(0);
  await expect(page.locator("#items > li")
    .getByRole("checkbox", { name: "Toggle item" })).toHaveCount(2);
  await expect(page.locator("#items-left")).toHaveText("2 items left of 2");
  await expect(page.locator("#items > li").first()).toHaveClass("item-row");
});

test("one payload broadcast's region touch updates the counts and every selection together (ADR-0061)", async ({ page }) => {
  await mountToggle(page);
  const box = page.getByRole("checkbox", { name: "Toggle all" });
  const clear = page.locator("button", { hasText: "Clear completed" });
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await page.locator("#items > li").first()
    .getByRole("checkbox", { name: "Toggle item" }).check();
  await expect(page.locator("#items-left")).toHaveText("1 item left of 2");
  await expect(clear).toBeVisible();
  await expect(box).not.toBeChecked();
  await page.evaluate(() => {
    globalThis.firstRow = document.querySelector("#items > li");
  });
  const metricsBefore = await regionMetrics(page);
  const before = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  // One change event, one transaction, one region touch: the broadcast
  // re-renders both retained rows, and the same commit sweep updates the
  // items-left counts, re-evaluates the clear-completed hidden (revealed,
  // equal-value), the list hidden (rows remain — no write), and the
  // toggle-all checked (flips to true) together.
  await box.check();
  await expect(page.locator("#items-left")).toHaveText("0 items left of 2");
  await expect(clear).toBeVisible();
  await expect(page.locator("#items")).toBeVisible();
  await expect(box).toBeChecked();
  const metricsAfter = await regionMetrics(page);
  expect(metricsAfter[0]).toBe(metricsBefore[0]);
  expect(metricsAfter[1]).toBe(metricsBefore[1] + 2);
  expect(metricsAfter[2]).toBe(metricsBefore[2]);
  expect(metricsAfter[3]).toBe(metricsBefore[3]);
  const retained = await page.evaluate(() =>
    globalThis.firstRow === document.querySelector("#items > li"),
  );
  expect(retained).toBe(true);
  const after = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  const count = (tx, label) => tx[7].filter((entry) => entry === label).length;
  expect(count(after, "event:toggleAll")).toBe(count(before, "event:toggleAll") + 1);
  expect(count(after, "region:items:broadcast"))
    .toBe(count(before, "region:items:broadcast") + 1);
  for (const label of [
    "attr:1:hidden:evaluated", "attr:2:hidden:evaluated",
    "attr:3:checked:evaluated",
  ]) {
    expect(count(after, label)).toBe(count(before, label) + 1);
  }
  expect(count(after, "dom:attr:3:checked:write"))
    .toBe(count(before, "dom:attr:3:checked:write") + 1);
  expect(count(after, "dom:attr:1:hidden:write"))
    .toBe(count(before, "dom:attr:1:hidden:write"));
  expect(count(after, "dom:attr:2:hidden:write"))
    .toBe(count(before, "dom:attr:2:hidden:write"));
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("an equal-payload broadcast is an evaluate-only sweep and an empty-region broadcast is a no-op (ADR-0061)", async ({ page }) => {
  await mountToggle(page);
  // Addressed by id: the box hides with the empty-list chrome once the
  // region drains, and the role query excludes hidden elements.
  const box = page.locator("#toggle-all");
  const count = (tx, label) => tx[7].filter((entry) => entry === label).length;
  const fireChange = (checked) =>
    page.evaluate((value) => {
      const element = document.getElementById("toggle-all");
      element.checked = value;
      element.dispatchEvent(new Event("change", { bubbles: true }));
    }, checked);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await box.check();
  await expect(box).toBeChecked();
  // An equal-payload broadcast — the "true" payload while every row is
  // already done — re-renders the retained rows to their equal values and
  // leaves the whole sweep evaluate-only: the counts, the hidden slots,
  // and the checked slot all compare equal and write nothing.
  const before = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  await fireChange(true);
  await expect(page.locator("#items-left")).toHaveText("0 items left of 2");
  await expect(box).toBeChecked();
  const after = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(count(after, "region:items:broadcast"))
    .toBe(count(before, "region:items:broadcast") + 1);
  expect(count(after, "attr:3:checked:evaluated"))
    .toBe(count(before, "attr:3:checked:evaluated") + 1);
  for (const label of [
    "dom:attr:1:hidden:write", "dom:attr:2:hidden:write",
    "dom:attr:3:checked:write",
  ]) {
    expect(count(after, label)).toBe(count(before, label));
  }
  // An empty-region broadcast touches no row: draining the region and
  // firing the uncheck payload runs the broadcast over zero rows — no
  // mount, no update, no disposal beyond the drain itself — and the sweep
  // stays evaluate-only (the vacuous truth still counts zero not-done
  // rows, so the cache does not flip and the DOM keeps the user's
  // gesture).
  await page.getByRole("button", { name: "Clear completed" }).click();
  await expect(page.locator("#items > li")).toHaveCount(0);
  const metricsBefore = await regionMetrics(page);
  const beforeEmpty = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  await fireChange(false);
  const afterEmpty = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  const metricsAfter = await regionMetrics(page);
  expect(metricsAfter).toEqual(metricsBefore);
  await expect(page.locator("#items > li")).toHaveCount(0);
  expect(count(afterEmpty, "event:toggleAll"))
    .toBe(count(beforeEmpty, "event:toggleAll") + 1);
  expect(count(afterEmpty, "attr:3:checked:evaluated"))
    .toBe(count(beforeEmpty, "attr:3:checked:evaluated") + 1);
  expect(count(afterEmpty, "dom:attr:3:checked:write"))
    .toBe(count(beforeEmpty, "dom:attr:3:checked:write"));
  expect(count(afterEmpty, "dom:attr:2:hidden:write"))
    .toBe(count(beforeEmpty, "dom:attr:2:hidden:write"));
  expect(await box.evaluate((element) => element.checked)).toBe(false);
});

test("the count label flips between singular and plural on the count sweep (ADR-0062)", async ({ page }) => {
  await mountToggle(page);
  const count = (tx, label) => tx[7].filter((entry) => entry === label).length;
  const instrumentation = () =>
    page.evaluate(() => globalThis.toggleDispose.instrumentation());
  // The label mounts as the plural branch: an empty region counts zero
  // not-done rows, and zero differs from the one literal, so the line
  // reads the else string before any transaction runs.
  await expect(page.locator("#items-left")).toHaveText("0 items left of 0");
  const add = page.getByRole("button", { name: "Add item" });
  // The first append flips the label to singular in exactly one evaluation
  // and one write: the recomputed predicate count equals the one literal,
  // the selected string differs from the cached plural, and the same
  // commit updates the numbers beside it.
  const beforeFirst = await instrumentation();
  await add.click();
  await expect(page.locator("#items-left")).toHaveText("1 item left of 1");
  const afterFirst = await instrumentation();
  expect(count(afterFirst, "count:items:1:evaluated"))
    .toBe(count(beforeFirst, "count:items:1:evaluated") + 1);
  expect(count(afterFirst, "dom:count:items:1:write"))
    .toBe(count(beforeFirst, "dom:count:items:1:write") + 1);
  // The second append flips it back to plural — another single write.
  await add.click();
  await expect(page.locator("#items-left")).toHaveText("2 items left of 2");
  const afterSecond = await instrumentation();
  expect(count(afterSecond, "count:items:1:evaluated"))
    .toBe(count(afterFirst, "count:items:1:evaluated") + 1);
  expect(count(afterSecond, "dom:count:items:1:write"))
    .toBe(count(afterFirst, "dom:count:items:1:write") + 1);
  // An equal-selection commit is evaluate-only: toggling one of three rows
  // moves the predicate count from three to two — both plural — so the
  // label slot evaluates without writing while the numbers beside it
  // update in the same commit.
  await add.click();
  await expect(page.locator("#items-left")).toHaveText("3 items left of 3");
  const beforeEqual = await instrumentation();
  await page.locator("#items > li").nth(0)
    .getByRole("checkbox", { name: "Toggle item" }).check();
  await expect(page.locator("#items-left")).toHaveText("2 items left of 3");
  const afterEqual = await instrumentation();
  expect(count(afterEqual, "count:items:1:evaluated"))
    .toBe(count(beforeEqual, "count:items:1:evaluated") + 1);
  expect(count(afterEqual, "dom:count:items:1:write"))
    .toBe(count(beforeEqual, "dom:count:items:1:write"));
  // A filter change alone touches no region: the label slot does not even
  // evaluate — the ADR-0051 non-touch pinned at the label position.
  const beforeFilter = await instrumentation();
  await page.getByRole("button", { name: "Show active" }).click();
  await expect(page.locator("#items-left")).toHaveText("2 items left of 3");
  const afterFilter = await instrumentation();
  expect(count(afterFilter, "count:items:1:evaluated"))
    .toBe(count(beforeFilter, "count:items:1:evaluated"));
  await page.getByRole("button", { name: "Show all" }).click();
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("the count label follows every region mutation in the same commit (ADR-0062)", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  // The toggle-all payload broadcast, the per-row toggle, clearCompleted,
  // and the ✕ removal all run the label through the same region-touch
  // sweep as the count numbers: number and label agree after every commit.
  const box = page.getByRole("checkbox", { name: "Toggle all" });
  await box.check();
  await expect(page.locator("#items-left")).toHaveText("0 items left of 2");
  await box.uncheck();
  await expect(page.locator("#items-left")).toHaveText("2 items left of 2");
  await page.locator("#items > li").nth(0)
    .getByRole("checkbox", { name: "Toggle item" }).check();
  await expect(page.locator("#items-left")).toHaveText("1 item left of 2");
  await page.getByRole("button", { name: "Clear completed" }).click();
  await expect(page.locator("#items-left")).toHaveText("1 item left of 1");
  await page.locator("#items > li").nth(0)
    .getByRole("button", { name: "Remove item" }).click();
  await expect(page.locator("#items-left")).toHaveText("0 items left of 0");
});

test("the empty-list chrome mounts hidden and one commit reveals it", async ({ page }) => {
  await mountToggle(page);
  const footer = page.locator("#footer");
  const box = page.locator("#toggle-all");
  // The footer wrapping the items-left line and the filter buttons, and the
  // toggle-all box, mount with their hidden property already true — the
  // ADR-0058 emptiness subject reused verbatim on two more attr slots,
  // written by mount before any transaction exists. The box carries hidden
  // beside its checked selection: two selections of different attributes
  // share one element because duplicate detection keys on the attribute
  // name (ADR-0045), so the vacuous checked truth and the emptiness hidden
  // coexist.
  expect(await footer.evaluate((element) => element.hidden)).toBe(true);
  expect(await box.evaluate((element) => element.hidden)).toBe(true);
  expect(await box.evaluate((element) => element.checked)).toBe(true);
  await expect(page.locator("#items")).toBeHidden();
  const count = (tx, label) => tx[7].filter((entry) => entry === label).length;
  // The first append reveals the list wrapper, the box, and the footer in
  // the same commit — one evaluation and one write per emptiness slot, all
  // three riding the one region-touch sweep.
  const before = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  await page.getByRole("button", { name: "Add item" }).click();
  const after = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  for (const label of [
    "attr:2:hidden:evaluated", "attr:4:hidden:evaluated",
    "attr:5:hidden:evaluated", "dom:attr:2:hidden:write",
    "dom:attr:4:hidden:write", "dom:attr:5:hidden:write",
  ]) {
    expect(count(after, label)).toBe(count(before, label) + 1);
  }
  await expect(footer).toBeVisible();
  await expect(page.locator("#items")).toBeVisible();
  expect(await box.evaluate((element) => element.hidden)).toBe(false);
  await expect(page.getByRole("button", { name: "Show active" })).toBeVisible();
  await expect(page.locator("#items-left")).toBeVisible();
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("every removal path re-hides the empty-list chrome", async ({ page }) => {
  await mountToggle(page);
  const footer = page.locator("#footer");
  const box = page.locator("#toggle-all");
  const add = page.getByRole("button", { name: "Add item" });
  const chromeHidden = () => page.evaluate(() => [
    document.getElementById("footer").hidden,
    document.getElementById("toggle-all").hidden,
  ]);
  // The ✕ removal drains the region: the same commit's sweep re-hides the
  // footer and the box beside the list wrapper.
  await add.click();
  await expect(footer).toBeVisible();
  await page.locator("#items > li").first()
    .getByRole("button", { name: "Remove item" }).click();
  expect(await chromeHidden()).toEqual([true, true]);
  // The guarded empty commit (ADR-0053) removes through the same reconcile.
  await add.click();
  await expect(footer).toBeVisible();
  await page.locator("#items > li").first().locator(".item-label").dblclick();
  const editor = page.locator("#items > li").first()
    .getByRole("textbox", { name: "Item editor" });
  await editor.fill("");
  await editor.press("Enter");
  await expect(page.locator("#items > li")).toHaveCount(0);
  expect(await chromeHidden()).toEqual([true, true]);
  // completeAll + clearCompleted drain the region through the predicate
  // removal — the broadcast leaves the chrome revealed, the drain hides it.
  await add.click();
  await add.click();
  await expect(footer).toBeVisible();
  await page.getByRole("button", { name: "Complete all" }).click();
  expect(await chromeHidden()).toEqual([false, false]);
  await page.getByRole("button", { name: "Clear completed" }).click();
  await expect(page.locator("#items > li")).toHaveCount(0);
  expect(await chromeHidden()).toEqual([true, true]);
  expect(await box.evaluate((element) => element.checked)).toBe(true);
});

test("a filter hiding every row keeps the chrome and a filter change never evaluates it", async ({ page }) => {
  await mountToggle(page);
  const footer = page.locator("#footer");
  const box = page.locator("#toggle-all");
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  const count = (tx, label) => tx[7].filter((entry) => entry === label).length;
  // Every row is active, so the completed filter hides all of them — but
  // the chrome's subject is the row table, not the displayed rows: the
  // footer and the box stay revealed around an all-hidden list, and the
  // filter change alone touches no region, so the emptiness slots are not
  // even re-evaluated.
  const before = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  await page.getByRole("button", { name: "Show completed" }).click();
  await expect(page.locator("#items > li:visible")).toHaveCount(0);
  const filtered = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  for (const label of [
    "attr:4:hidden:evaluated", "attr:5:hidden:evaluated",
  ]) {
    expect(count(filtered, label)).toBe(count(before, label));
  }
  expect(await footer.evaluate((element) => element.hidden)).toBe(false);
  expect(await box.evaluate((element) => element.hidden)).toBe(false);
  await expect(page.locator("#items-left")).toHaveText("2 items left of 2");
  // Appending while filtered re-evaluates the slots on the region touch but
  // writes nothing: the chrome is already revealed.
  await add.click();
  const appended = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  for (const label of [
    "attr:4:hidden:evaluated", "attr:5:hidden:evaluated",
  ]) {
    expect(count(appended, label)).toBe(count(filtered, label) + 1);
  }
  for (const label of [
    "dom:attr:4:hidden:write", "dom:attr:5:hidden:write",
  ]) {
    expect(count(appended, label)).toBe(count(filtered, label));
  }
  await page.getByRole("button", { name: "Show all" }).click();
  await expect(page.locator("#items > li:visible")).toHaveCount(3);
});

test("Escape clears the new-todo draft through the unguarded component arm (ADR-0056)", async ({ page }) => {
  await mountToggle(page);
  const draft = page.getByRole("textbox", { name: "New todo" });
  const addTodo = page.getByRole("button", { name: "Add todo" });
  const count = (tx, label) => tx[7].filter((entry) => entry === label).length;
  await draft.fill("  buy milk ");
  await expect(addTodo).toBeEnabled();
  const beforeRegion = await regionMetrics(page);
  const before = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  // The Escape arm is unguarded: it commits unconditionally — one
  // transaction traced under its own event:confirmAdd:Escape label, the
  // draft reset to the empty literal, the controlled input following
  // through the ADR-0038 reflection, and the Add affordance re-disabling
  // through its ADR-0057 selection in the same commit. No region is
  // touched: the revert is a component-scope write only.
  await draft.press("Escape");
  await expect(draft).toHaveValue("");
  await expect(addTodo).toBeDisabled();
  const after = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  for (const label of [
    "event:confirmAdd:Escape", "transaction:begin", "dom:prop:0:value:write",
    "attr:0:disabled:evaluated", "dom:attr:0:disabled:write",
  ]) {
    expect(count(after, label)).toBe(count(before, label) + 1);
  }
  expect(count(after, "region:items:append")).toBe(count(before, "region:items:append"));
  expect(await regionMetrics(page)).toEqual(beforeRegion);
  await expect(page.locator("#items > li")).toHaveCount(0);
  // Escape on an already-empty draft still runs the unconditional commit —
  // the transaction shell and the event trace appear — but the equal-value
  // draft leaves the changed flag down: no prop write, no attr evaluation.
  const beforeEqual = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  await draft.press("Escape");
  const afterEqual = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(count(afterEqual, "event:confirmAdd:Escape"))
    .toBe(count(beforeEqual, "event:confirmAdd:Escape") + 1);
  expect(count(afterEqual, "transaction:begin"))
    .toBe(count(beforeEqual, "transaction:begin") + 1);
  expect(count(afterEqual, "dom:prop:0:value:write"))
    .toBe(count(beforeEqual, "dom:prop:0:value:write"));
  expect(count(afterEqual, "attr:0:disabled:evaluated"))
    .toBe(count(beforeEqual, "attr:0:disabled:evaluated"));
  // Enter after the revert hits the ADR-0055 skip guard as a whole-event
  // no-op: the reverted draft is empty, so the dispatch returns before any
  // transaction exists.
  const beforeEnter = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  await draft.press("Enter");
  await expect(page.locator("#items > li")).toHaveCount(0);
  const afterEnter = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(afterEnter).toEqual(beforeEnter);
  // A key outside the sealed arm table still moves nothing.
  await draft.press("ArrowLeft");
  const afterOther = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(afterOther).toEqual(afterEnter);
});

test("the hash seeds the filter at mount (ADR-0063)", async ({ page }) => {
  await page.goto(origin);
  await page.evaluate(async () => {
    location.hash = "#/completed";
    const { mount } = await import("/ToggleLab.mjs");
    globalThis.toggleDispose = mount(document.getElementById("app"));
  });
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  // The mount seed folded "#/completed" into the filter slot before the DOM
  // mounted, so the appending commit's filter sweep hides the fresh active
  // rows immediately — and the counts stay filter-independent.
  await expect(page.locator("#items > li")).toHaveCount(2);
  await expect(page.locator("#items > li:visible")).toHaveCount(0);
  await expect(page.locator("#items-left")).toHaveText("2 items left of 2");
  // Toggling a filter-hidden row done keeps the seeded filter live: the
  // done row joins the completed set and becomes visible (the synthetic
  // click reaches the delegated listener — the dispatch, not the
  // affordance, carries the contract).
  await page.locator("#items > li").first()
    .getByRole("checkbox", { name: "Toggle item", includeHidden: true })
    .evaluate((box) => box.click());
  await expect(page.locator("#items > li:visible")).toHaveCount(1);
});

test("an unknown hash keeps the declared default at mount (ADR-0063)", async ({ page }) => {
  await page.goto(origin);
  await page.evaluate(async () => {
    location.hash = "#/bogus";
    const { mount } = await import("/ToggleLab.mjs");
    globalThis.toggleDispose = mount(document.getElementById("app"));
  });
  // A hash outside the sealed table falls to the declared "all" default:
  // every appended row is displayed.
  await page.getByRole("button", { name: "Add item" }).click();
  await expect(page.locator("#items > li:visible")).toHaveCount(1);
});

test("hashchange dispatches the filter set-field transaction (ADR-0063)", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await page.locator("#items > li").first()
    .getByRole("checkbox", { name: "Toggle item" }).check();
  // Navigating the hash dispatches exactly the set-field transaction the
  // filter buttons dispatch — the whole commit path reused: selection,
  // filter sweep, and counts together, traced under the arm's own label.
  await page.evaluate(() => {
    location.hash = "#/active";
  });
  await expect(page.locator("#items > li").first()).toBeHidden();
  await expect(page.locator("#items > li").nth(1)).toBeVisible();
  await expect(page.locator("#items-left")).toHaveText("1 item left of 2");
  const trace = await page.evaluate(() => globalThis.toggleDispose.instrumentation()[7]);
  expect(trace).toContain("event:route:filter:active");
  // An unknown hash dispatches the default arm: the filter falls back to
  // "all" and every retained row shows again.
  await page.evaluate(() => {
    location.hash = "#/bogus";
  });
  await expect(page.locator("#items > li:visible")).toHaveCount(2);
});

test("filter buttons write the canonical hash flip-only with no echo loop (ADR-0063)", async ({ page }) => {
  await mountToggle(page);
  await page.getByRole("button", { name: "Add item" }).click();
  const count = (tx, label) => tx[7].filter((entry) => entry === label).length;
  // The set-field commit writes the canonical hash literal behind the
  // field's changed flag: one route write for the flip.
  await page.getByRole("button", { name: "Show active" }).click();
  await expect(page).toHaveURL(/#\/active$/);
  const after = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(count(after, "route:filter:write")).toBe(1);
  // The hash write itself fires one hashchange, whose dispatch is an
  // equal-value set-field commit: changed stays false, so no second route
  // write exists once the echo settles — no loop.
  await page.waitForTimeout(100);
  const settled = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(count(settled, "route:filter:write")).toBe(1);
  // Re-dispatching the same filter is an equal-value commit: still no
  // route write.
  await page.getByRole("button", { name: "Show active" }).click();
  await page.waitForTimeout(100);
  const again = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(count(again, "route:filter:write")).toBe(1);
  await page.getByRole("button", { name: "Show all" }).click();
  await expect(page).toHaveURL(/#\/$/);
});

test("region commits persist the row table and a remount hydrates it (ADR-0063)", async ({ page }) => {
  await mountToggle(page);
  const draft = page.getByRole("textbox", { name: "New todo" });
  // A label carrying every separator and the escape character round-trips
  // through the sealed split/join encoding.
  await draft.fill("milk, eggs; 100%");
  await draft.press("Enter");
  await page.getByRole("button", { name: "Add item" }).click();
  await page.locator("#items > li").first()
    .getByRole("checkbox", { name: "Toggle item" }).check();
  const stored = await page.evaluate(() =>
    localStorage.getItem("leanrx-toggle-lab.items"));
  expect(stored).toBe(
    "milk%2C eggs%3B 100%25,milk%2C eggs%3B 100%25,true,view;Item 0,Item 0,false,view",
  );
  // A fresh mount hydrates through one ordinary transaction: rows, toggle
  // state, counts, chrome, and the normalized write-back all settle in the
  // shared commit sweep.
  await page.reload();
  await page.evaluate(async () => {
    const { mount } = await import("/ToggleLab.mjs");
    globalThis.toggleDispose = mount(document.getElementById("app"));
  });
  await expect(page.locator("#items > li .item-label")).toHaveText([
    "milk, eggs; 100%", "Item 0",
  ]);
  await expect(page.locator("#items > li").first()
    .getByRole("checkbox", { name: "Toggle item" })).toBeChecked();
  await expect(page.locator("#items > li").first()).toHaveClass("item-row done");
  await expect(page.locator("#items-left")).toHaveText("1 item left of 2");
  await expect(page.locator("#items")).toBeVisible();
  const trace = await page.evaluate(() => globalThis.toggleDispose.instrumentation()[7]);
  expect(trace).toContain("event:hydrate:items");
  expect(trace).toContain("region:items:hydrate");
  expect(trace).toContain("storage:items:write");
  // Hydrated rows are full citizens of the row vocabulary: the region
  // metrics count their mounts and the editor opens on the mirrored draft.
  const metrics = await regionMetrics(page);
  expect(metrics[0]).toBe(2);
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  await expect(page.locator("#items > li").nth(0)
    .getByRole("textbox", { name: "Item editor" })).toHaveValue("milk, eggs; 100%");
});

test("a wrong-arity stored value fails closed to the empty region (ADR-0063)", async ({ page }) => {
  await page.goto(origin);
  await page.evaluate(async () => {
    localStorage.setItem("leanrx-toggle-lab.items", "only,two");
    const { mount } = await import("/ToggleLab.mjs");
    globalThis.toggleDispose = mount(document.getElementById("app"));
  });
  // The two-field row disagrees with the declared four-field arity: the
  // whole value hydrates nothing and the chrome keeps its empty-mount
  // state — fail closed, no throw, no partial row.
  await expect(page.locator("#items > li")).toHaveCount(0);
  await expect(page.locator("#items")).toBeHidden();
  await expect(page.locator("#items-left")).toHaveText("0 items left of 0");
  const trace = await page.evaluate(() => globalThis.toggleDispose.instrumentation()[7]);
  expect(trace).toContain("event:hydrate:items");
  expect(trace).not.toContain("region:items:hydrate");
  // The next region-touching commit overwrites the stale value with the
  // normalized four-field serialization.
  await page.getByRole("button", { name: "Add item" }).click();
  expect(await page.evaluate(() => localStorage.getItem("leanrx-toggle-lab.items")))
    .toBe("Item 0,Item 0,false,view");
});

test("a filter change alone persists nothing; one storageSet per region touch (ADR-0063)", async ({ page }) => {
  await mountToggle(page);
  await page.getByRole("button", { name: "Add item" }).click();
  const count = (tx, label) => tx[7].filter((entry) => entry === label).length;
  const before = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  // Mount hydrated an absent value (no touch, no write); the append is the
  // first region touch and therefore the first storageSet.
  expect(count(before, "storage:items:write")).toBe(1);
  // The filter change is not a region touch: no serialization, no write —
  // the stored value is byte-identical afterwards, echo dispatch included.
  await page.getByRole("button", { name: "Show active" }).click();
  await page.waitForTimeout(100);
  const filtered = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(count(filtered, "storage:items:write")).toBe(1);
  expect(await page.evaluate(() => localStorage.getItem("leanrx-toggle-lab.items")))
    .toBe("Item 0,Item 0,false,view");
  // A row toggle is a region touch: exactly one more storageSet, carrying
  // the flipped done field.
  await page.locator("#items > li").first()
    .getByRole("checkbox", { name: "Toggle item" }).check();
  const toggled = await page.evaluate(() => globalThis.toggleDispose.instrumentation());
  expect(count(toggled, "storage:items:write")).toBe(2);
  expect(await page.evaluate(() => localStorage.getItem("leanrx-toggle-lab.items")))
    .toBe("Item 0,Item 0,true,view");
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

test("each row event wakes only the sweeps its own stage can move (ADR-0084)", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  // Every sweep this region carries, by the flag ADR-0084 assigns it inside
  // the region's own dispatch function: the two `done` predicate counts, the
  // two `done` predicate selections and the filter table read the `toggle`
  // class; the editing hint reads the `edit`/`commit`/`keys` class; the row
  // total and the three emptiness subjects stay behind the structural bit;
  // the persistence write-back reads every field and can never narrow.
  const reads = (tx) => ({
    doneCount: tx[7].filter((entry) => entry === "count:items:0:evaluated").length,
    doneLabel: tx[7].filter((entry) => entry === "count:items:1:evaluated").length,
    total: tx[7].filter((entry) => entry === "count:items:2:evaluated").length,
    clearHidden: tx[7].filter((entry) => entry === "attr:1:hidden:evaluated").length,
    toggleAll: tx[7].filter((entry) => entry === "attr:3:checked:evaluated").length,
    hint: tx[7].filter((entry) => entry === "attr:6:hidden:evaluated").length,
    filter: tx[7].filter((entry) => entry === "filter:items:evaluated").length,
    stored: tx[7].filter((entry) => entry === "storage:items:write").length,
    drained: tx[7].filter((entry) => entry === "region:items:updateAt").length,
    sinkEvaluations: tx[5],
    attrEvaluations: tx[8],
  });
  const instrumentation = () =>
    page.evaluate(() => globalThis.toggleDispose.instrumentation());

  // `edit` writes `mode`: the editing hint's scan is the one row walk it
  // wakes. The `done` sweeps and the filter table cannot move on it.
  const beforeEdit = reads(await instrumentation());
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  const editor = page.locator("#items > li").nth(0)
    .getByRole("textbox", { name: "Item editor" });
  await expect(editor).toBeFocused();
  await expect(page.locator("#edit-hint")).toBeVisible();
  const afterEdit = reads(await instrumentation());
  expect(afterEdit.hint).toBe(beforeEdit.hint + 1);
  expect(afterEdit.doneCount).toBe(beforeEdit.doneCount);
  expect(afterEdit.doneLabel).toBe(beforeEdit.doneLabel);
  expect(afterEdit.clearHidden).toBe(beforeEdit.clearHidden);
  expect(afterEdit.toggleAll).toBe(beforeEdit.toggleAll);
  expect(afterEdit.filter).toBe(beforeEdit.filter);
  expect(afterEdit.total).toBe(beforeEdit.total);
  expect(afterEdit.drained).toBe(beforeEdit.drained + 1);
  expect(afterEdit.stored).toBe(beforeEdit.stored + 1);

  // `retype` writes `draft`, which nothing but the persistence write-back
  // reads: one keystroke drains one row, re-serializes the table, and
  // re-evaluates nothing at all — not one count, not one selection, not the
  // filter sweep. The keydown beside it matches no arm, so it queues
  // nothing and wakes nothing either.
  const beforeType = reads(await instrumentation());
  await editor.pressSequentially("!");
  await expect(editor).toHaveValue("Item 0!");
  const afterType = reads(await instrumentation());
  expect(afterType.doneCount).toBe(beforeType.doneCount);
  expect(afterType.doneLabel).toBe(beforeType.doneLabel);
  expect(afterType.total).toBe(beforeType.total);
  expect(afterType.clearHidden).toBe(beforeType.clearHidden);
  expect(afterType.toggleAll).toBe(beforeType.toggleAll);
  expect(afterType.hint).toBe(beforeType.hint);
  expect(afterType.filter).toBe(beforeType.filter);
  expect(afterType.sinkEvaluations).toBe(beforeType.sinkEvaluations);
  expect(afterType.attrEvaluations).toBe(beforeType.attrEvaluations);
  // The drain itself still happened, and persistence still paid for it.
  expect(afterType.drained).toBe(beforeType.drained + 1);
  expect(afterType.stored).toBe(beforeType.stored + 1);
  // Both row roots keep the `hidden` byte the last sweep that ran wrote.
  expect(await page.locator("#items > li").nth(0).evaluate((row) => row.hidden)).toBe(false);
  expect(await page.locator("#items > li").nth(1).evaluate((row) => row.hidden)).toBe(false);

  // `keys` Escape writes `draft` and `mode`: the hint's class wakes, the
  // `done` class still does not.
  const beforeEscape = reads(await instrumentation());
  await editor.press("Escape");
  await expect(page.locator("#items > li").nth(0).locator(".item-label"))
    .toHaveText("Item 0");
  const afterEscape = reads(await instrumentation());
  expect(afterEscape.hint).toBe(beforeEscape.hint + 1);
  expect(afterEscape.doneCount).toBe(beforeEscape.doneCount);
  expect(afterEscape.filter).toBe(beforeEscape.filter);

  // `toggle` writes `done`: the mirror image — every `done` sweep and the
  // filter table run, the editing hint does not, and the row total stays
  // behind the structural bit.
  const beforeToggle = reads(await instrumentation());
  await page.locator("#items > li").nth(1)
    .getByRole("checkbox", { name: "Toggle item" }).check();
  const afterToggle = reads(await instrumentation());
  expect(afterToggle.doneCount).toBe(beforeToggle.doneCount + 1);
  expect(afterToggle.doneLabel).toBe(beforeToggle.doneLabel + 1);
  expect(afterToggle.clearHidden).toBe(beforeToggle.clearHidden + 1);
  expect(afterToggle.toggleAll).toBe(beforeToggle.toggleAll + 1);
  expect(afterToggle.filter).toBe(beforeToggle.filter + 1);
  expect(afterToggle.hint).toBe(beforeToggle.hint);
  expect(afterToggle.total).toBe(beforeToggle.total);
  expect(afterToggle.drained).toBe(beforeToggle.drained + 1);

  // An append is structural: every sweep the region carries runs, whichever
  // flag it reads.
  const beforeAppend = reads(await instrumentation());
  await add.click();
  await expect(page.locator("#items > li")).toHaveCount(3);
  const afterAppend = reads(await instrumentation());
  expect(afterAppend.total).toBe(beforeAppend.total + 1);
  expect(afterAppend.doneCount).toBe(beforeAppend.doneCount + 1);
  expect(afterAppend.hint).toBe(beforeAppend.hint + 1);
  expect(afterAppend.filter).toBe(beforeAppend.filter + 1);
  expect(afterAppend.drained).toBe(beforeAppend.drained);
});

test("the serialization cache re-encodes exactly the rows a write staled (ADR-0085)", async ({ page }) => {
  await mountToggle(page);
  // The one trace entry the ADR-0085 sweep reports: how many rows it had to
  // encode, which is the number whose cache cell a write staled since the
  // previous write-back. Every other row was read back out of its own tuple.
  const encodes = (tx) =>
    tx[7].filter((entry) => entry.startsWith("storage:items:encode:"))
      .map((entry) => Number(entry.slice("storage:items:encode:".length)));
  const since = async (before) =>
    encodes(await page.evaluate(() => globalThis.toggleDispose.instrumentation()))
      .slice(before.length);
  const now = async () =>
    encodes(await page.evaluate(() => globalThis.toggleDispose.instrumentation()));
  const stored = () =>
    page.evaluate(() => localStorage.getItem("leanrx-toggle-lab.items"));

  // Mount hydrated an absent value: no region touch, so no write-back and no
  // encode at all.
  expect(await now()).toEqual([]);

  // An append is structural — every sweep runs — but only the appended row
  // is born unencoded, so the write-back encodes one row and reads the rest
  // back. Three appends, one encode each.
  const add = page.getByRole("button", { name: "Add item" });
  let mark = await now();
  await add.click();
  await add.click();
  await add.click();
  await expect(page.locator("#items > li")).toHaveCount(3);
  expect(await since(mark)).toEqual([1, 1, 1]);
  expect(await stored()).toBe(
    "Item 0,Item 0,false,view;Item 1,Item 1,false,view;Item 2,Item 2,false,view");

  // A `toggle` writes one row's `done`: one encode, two rows read back.
  mark = await now();
  await page.locator("#items > li").nth(1)
    .getByRole("checkbox", { name: "Toggle item" }).check();
  expect(await since(mark)).toEqual([1]);
  expect(await stored()).toBe(
    "Item 0,Item 0,false,view;Item 1,Item 1,true,view;Item 2,Item 2,false,view");

  // A filter change is not a region touch: no write-back, so no encode
  // either — and the cache is untouched by the sweep that does run.
  mark = await now();
  await page.getByRole("button", { name: "Show active" }).click();
  await page.waitForTimeout(100);
  expect(await since(mark)).toEqual([]);
  await page.getByRole("button", { name: "Show all" }).click();
  await page.waitForTimeout(100);

  // `edit`, each `retype` keystroke, and the Enter commit each write the
  // dispatching row and nothing else: one encode per commit however many
  // rows the region holds.
  mark = await now();
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  const editor = page.locator("#items > li").nth(0)
    .getByRole("textbox", { name: "Item editor" });
  await editor.pressSequentially("ab");
  await editor.press("Enter");
  await expect(page.locator("#items > li").nth(0).locator(".item-label"))
    .toHaveText("Item 0ab");
  expect(await since(mark)).toEqual([1, 1, 1, 1]);
  expect(await stored()).toBe(
    "Item 0ab,Item 0ab,false,view;Item 1,Item 1,true,view;Item 2,Item 2,false,view");

  // A removal writes no field: the kept-filter rebuilds the row array around
  // the *same* row tuples, so every survivor's cell is still valid and the
  // write-back encodes nothing at all.
  mark = await now();
  await page.locator("#items > li").nth(2)
    .getByRole("button", { name: "Remove item" }).click();
  await expect(page.locator("#items > li")).toHaveCount(2);
  expect(await since(mark)).toEqual([0]);
  expect(await stored()).toBe("Item 0ab,Item 0ab,false,view;Item 1,Item 1,true,view");

  // The ADR-0050 predicate removal is the same shape: rows leave, no field
  // is written, nothing re-encodes.
  mark = await now();
  await page.getByRole("button", { name: "Clear completed" }).click();
  await expect(page.locator("#items > li")).toHaveCount(1);
  expect(await since(mark)).toEqual([0]);
  expect(await stored()).toBe("Item 0ab,Item 0ab,false,view");

  // A broadcast writes *every* row, so it stales every cell: the one write
  // path whose invalidation is O(N), and the reason the write-back keeps the
  // region-wide flag.
  await add.click();
  mark = await now();
  await page.getByRole("button", { name: "Complete all" }).click();
  expect(await since(mark)).toEqual([2]);
  expect(await stored()).toBe("Item 0ab,Item 0ab,true,view;Item 3,Item 3,true,view");

  // The ADR-0061 payload broadcast is the same: two rows written, two
  // encoded, and the stored value follows.
  mark = await now();
  await page.getByRole("checkbox", { name: "Toggle all" }).uncheck();
  expect(await since(mark)).toEqual([2]);
  expect(await stored()).toBe("Item 0ab,Item 0ab,false,view;Item 3,Item 3,false,view");

  // Hydration arrives with unencoded cells, so the mount write-back encodes
  // the whole table once — which is what normalizes a hand-edited stored
  // value, exactly as ADR-0063 promised.
  await page.reload();
  await page.evaluate(async () => {
    localStorage.setItem("leanrx-toggle-lab.items", "raw%25,raw%25,false,view;b,b,true,view");
    const { mount } = await import("/ToggleLab.mjs");
    globalThis.toggleDispose = mount(document.getElementById("app"));
  });
  await expect(page.locator("#items > li")).toHaveCount(2);
  expect(await now()).toEqual([2]);
  expect(await stored()).toBe("raw%25,raw%25,false,view;b,b,true,view");
});

test("the store is current at the end of every commit, not of the task (ADR-0087)", async ({ page }) => {
  await mountToggle(page);
  const count = (tx, label) => tx[7].filter((entry) => entry === label).length;
  const instrumentation = () =>
    page.evaluate(() => globalThis.toggleDispose.instrumentation());
  const before = await instrumentation();

  // Three dispatches inside *one* task: the clicks are synchronous, so the
  // browser never gets a turn between them. This is the shape a per-task
  // flush would have collapsed into a single join and a single storageSet
  // (ADR-0087 measured that at 3.4x on ten thousand rows) — and the shape
  // that would have left every intermediate value unobservable. Under the
  // per-commit contract each re-read, taken before the next click, already
  // sees what the commit that just returned wrote.
  const seen = await page.evaluate(() => {
    const button = Array.from(document.querySelectorAll("button"))
      .find((node) => node.textContent === "Add item");
    const observed = [];
    for (let index = 0; index < 3; index += 1) {
      button.click();
      observed.push(localStorage.getItem("leanrx-toggle-lab.items"));
    }
    return observed;
  });
  expect(seen).toEqual([
    "Item 0,Item 0,false,view",
    "Item 0,Item 0,false,view;Item 1,Item 1,false,view",
    "Item 0,Item 0,false,view;Item 1,Item 1,false,view;Item 2,Item 2,false,view",
  ]);

  // One commit per dispatch and one write per commit: nothing was coalesced
  // across the burst, and no write is still pending now that the task ended.
  const burst = await instrumentation();
  expect(count(burst, "transaction:commit") - count(before, "transaction:commit")).toBe(3);
  expect(count(burst, "storage:items:write") - count(before, "storage:items:write")).toBe(3);

  // A filter click in the same task as an append still writes exactly once:
  // the flush rides the region touch, not the task, so the untouched-region
  // commit contributes no write and the store is byte-identical across it.
  const mixed = await page.evaluate(() => {
    const button = (label) => Array.from(document.querySelectorAll("button"))
      .find((node) => node.textContent === label);
    button("Add item").click();
    const afterAppend = localStorage.getItem("leanrx-toggle-lab.items");
    button("Show active").click();
    return [afterAppend, localStorage.getItem("leanrx-toggle-lab.items")];
  });
  expect(mixed[1]).toBe(mixed[0]);
  // The hash write's echo dispatch lands in a later task and touches no
  // region either, so the whole mixed task is one write.
  await page.waitForTimeout(100);
  const settled = await instrumentation();
  expect(count(settled, "storage:items:write") - count(burst, "storage:items:write")).toBe(1);

  // What the contract buys: a tab closed at any point in either task loses
  // nothing a returned dispatch wrote. A remount hydrates all four rows out
  // of the store without any flush having been owed to unload.
  await page.reload();
  await page.evaluate(async () => {
    const { mount } = await import("/ToggleLab.mjs");
    globalThis.toggleDispose = mount(document.getElementById("app"));
  });
  await expect(page.locator("#items > li .item-label")).toHaveText([
    "Item 0", "Item 1", "Item 2", "Item 3",
  ]);
});

test("one commit walks a region's row table once per wake class (ADR-0088)", async ({ page }) => {
  await mountToggle(page);

  // The instrument: a counting `Symbol.iterator` on Array.prototype, installed
  // around one synchronous dispatch and removed before the page gets a turn.
  // It counts only traversals of *this region's row table* — an array whose
  // first element is a seven-cell row tuple `[key, label, draft, done, mode,
  // serial, shown]` behind a numeric key — so the pending-position array, the
  // hydration split and the region runtime's entry list stay invisible to it.
  // What it returns is exactly "how many times did this dispatch walk the
  // rows", which is the quantity ADR-0088 is about.
  const walks = (source) =>
    page.evaluate((code) => {
      const original = Array.prototype[Symbol.iterator];
      let counted = 0;
      Array.prototype[Symbol.iterator] = function counting() {
        const head = this[0];
        if (Array.isArray(head) && head.length === 7 && typeof head[0] === "number") {
          counted += 1;
        }
        return original.call(this);
      };
      try {
        new Function(code)();
      } finally {
        Array.prototype[Symbol.iterator] = original;
      }
      return counted;
    }, source);

  const clickButton = (label) =>
    `Array.from(document.querySelectorAll("button")).find((node) => node.textContent === ${JSON.stringify(label)}).click();`;

  await page.getByRole("button", { name: "Add item" }).click();
  await page.getByRole("button", { name: "Add item" }).click();
  await page.getByRole("button", { name: "Add item" }).click();
  await expect(page.locator("#items > li")).toHaveCount(3);

  // A `toggle` on three rows, not ten thousand. The dispatch resolves the row
  // by its key scan (1); the drain-class-0 sweeps share one pass over the two
  // `done` predicates (2) — before ADR-0088 that was four separate passes, two
  // counts and two selections, three of them spelling the identical
  // `done == "false"`; and the ADR-0051 filter sweep and the ADR-0063
  // persistence sweep follow the reconcile with one walk each (3, 4). Seven
  // before, four now, with every label, counter, cache and write unmoved.
  expect(await walks('document.querySelectorAll("#items input[type=checkbox]")[0].click();')).toBe(4);

  // ADR-0084's control, unmoved: a keystroke inside a row editor writes
  // `draft`, which no predicate scan reads, so the commit runs no pass at all
  // and the key scan and the write-back are the only two walks. This is why
  // the survey measured `retype` flat at 1.00x across every fusion rung.
  await page.locator("#items > li .item-label").first().dblclick();
  expect(await walks(`
    const editor = document.querySelector("#items input[aria-label='Item editor']");
    editor.value = "typed";
    editor.dispatchEvent(new Event("input", { bubbles: true }));
  `)).toBe(2);
  await page.keyboard.press("Escape");

  // The contract's edge, and the whole reason the pass is keyed on the wake
  // class: the editing hint reads `mode`, so it sits in drain class 1. A
  // `dblclick` wakes that class and nothing else, so the hint evaluates
  // through its *own* loop (2) while the drain-class-0 pass stays asleep.
  // Fusing the two classes into one pass would have dragged the wider class
  // awake here — the survey priced that widening at 40% of the opportunity.
  expect(await walks('document.querySelectorAll("#items .item-label")[1].dispatchEvent(new MouseEvent("dblclick", { bubbles: true }));')).toBe(3);
  await page.keyboard.press("Escape");

  // A filter click touches no region, so no count and no selection wakes: the
  // filter sweep is the commit's only walk. It is not a fusion target either —
  // it runs after the reconcile, where a shared pass cannot follow it.
  expect(await walks(clickButton("Show active"))).toBe(1);
  await page.getByRole("button", { name: "Show all" }).click();

  // Outside the region's own dispatch function no class can be told apart, so
  // every predicate scan reads the touched flag and all five collapse into one
  // pass. An append walks the shared pass (1), the filter sweep (2) and the
  // persistence sweep (3); before ADR-0088 it walked seven.
  expect(await walks(clickButton("Add item"))).toBe(3);

  // A broadcast adds its own write loop over the rows ahead of the same three.
  expect(await walks(clickButton("Complete all"))).toBe(4);

  // The instrument left nothing behind, and every slot still agrees with the
  // DOM: what the pass shares is the traversal, never the cache.
  await expect(page.locator("#items-left strong")).toHaveText("0");
  await expect(page.locator("#toggle-all")).toBeChecked();
  await expect(page.locator("#items > li")).toHaveCount(4);
});
