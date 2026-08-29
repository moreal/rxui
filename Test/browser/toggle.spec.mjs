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

test("a sealed single-row removal reconciles nothing (ADR-0097)", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  for (let index = 0; index < 5; index += 1) await add.click();
  await page.evaluate(() => {
    globalThis.survivors = [...document.querySelectorAll("#items > li")]
      .filter((_, index) => index !== 2);
  });
  const before = await regionMetrics(page);
  const beforeTrace = await page.evaluate(() =>
    globalThis.toggleDispose.instrumentation()[7].length);
  // The ✕ button on the middle row. ADR-0092 already resolved its position
  // by binary search; ADR-0097 keeps that position and hands it to the
  // region handle's `removeAt` at commit.
  await page.locator("#items > li").nth(2).getByRole("button", { name: "Remove item" }).click();
  await expect(page.locator("#items > li .item-label"))
    .toHaveText(["Item 0", "Item 1", "Item 3", "Item 4"]);
  // Every survivor keeps the exact DOM node it had, on both sides of the
  // hole: `removeAt` shifts positions without touching nodes.
  const retained = await page.evaluate(() =>
    globalThis.survivors.every((node, index) =>
      node === document.querySelectorAll("#items > li")[index]));
  expect(retained).toBe(true);
  const after = await regionMetrics(page);
  // [mounts, updates, moves, disposals]: one disposal and nothing else. The
  // reconcile would have re-run the generated row-update callback on all
  // four survivors; this is the whole axis, read off the host's own counters.
  expect(after[0]).toBe(before[0]);
  expect(after[1]).toBe(before[1]);
  expect(after[2]).toBe(before[2]);
  expect(after[3]).toBe(before[3] + 1);
  const trace = await page.evaluate((from) =>
    globalThis.toggleDispose.instrumentation()[7].slice(from), beforeTrace);
  expect(trace.filter((entry) => entry === "region:items:removeAt").length).toBe(1);
  expect(trace.filter((entry) => entry === "region:items:update").length).toBe(0);
  // The removal is a structural change however it is recorded, so every
  // sweep the row set can move still ran in the same commit: the counts, the
  // filter table, and the persistence write-back.
  expect(trace.filter((entry) => entry === "count:items:2:evaluated").length).toBe(1);
  expect(trace.filter((entry) => entry === "filter:items:evaluated").length).toBe(1);
  expect(trace.filter((entry) => entry === "storage:items:write").length).toBe(1);
  await expect(page.locator("#items-left")).toHaveText("4 items left of 4");

  // The contrast, in the same component: the ADR-0050 predicate removal
  // takes an unbounded number of rows and keeps the reconcile, so it still
  // updates every survivor.
  await page.locator("#items > li").nth(0).getByRole("checkbox", { name: "Toggle item" }).check();
  const beforeClear = await regionMetrics(page);
  const clearFrom = await page.evaluate(() =>
    globalThis.toggleDispose.instrumentation()[7].length);
  await page.getByRole("button", { name: "Clear completed" }).click();
  await expect(page.locator("#items > li")).toHaveCount(3);
  const afterClear = await regionMetrics(page);
  expect(afterClear[3]).toBe(beforeClear[3] + 1);
  expect(afterClear[1]).toBe(beforeClear[1] + 3);
  const clearTrace = await page.evaluate((from) =>
    globalThis.toggleDispose.instrumentation()[7].slice(from), clearFrom);
  expect(clearTrace.filter((entry) => entry === "region:items:update").length).toBe(1);
  expect(clearTrace.filter((entry) => entry === "region:items:removeAt").length).toBe(0);
});

test("removing every row one at a time never reconciles and empties the region (ADR-0097)", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  for (let index = 0; index < 4; index += 1) await add.click();
  const before = await regionMetrics(page);
  const from = await page.evaluate(() =>
    globalThis.toggleDispose.instrumentation()[7].length);
  // Front, back, then what is left: the drain's position is whatever the key
  // search resolved at the time, so no order is special to it.
  for (const nth of [0, 2, 1, 0]) {
    await page.locator("#items > li").nth(nth)
      .getByRole("button", { name: "Remove item" }).click();
  }
  await expect(page.locator("#items > li")).toHaveCount(0);
  const after = await regionMetrics(page);
  expect(after[0]).toBe(before[0]);
  expect(after[1]).toBe(before[1]);
  expect(after[2]).toBe(before[2]);
  expect(after[3]).toBe(before[3] + 4);
  const trace = await page.evaluate((start) =>
    globalThis.toggleDispose.instrumentation()[7].slice(start), from);
  expect(trace.filter((entry) => entry === "region:items:removeAt").length).toBe(4);
  expect(trace.filter((entry) => entry === "region:items:update").length).toBe(0);
  // The emptied region takes the ADR-0058 visibility sweep and the ADR-0063
  // write-back exactly as the reconcile left it, and a fresh append into the
  // drained region mounts one row through the ADR-0098 drain.
  await expect(page.locator("#items")).toBeHidden();
  await expect(page.locator("#items-left")).toHaveText("0 items left of 0");
  const afterEmpty = await page.evaluate(() =>
    globalThis.localStorage.getItem("leanrx-toggle-lab.items"));
  expect(afterEmpty).toBe("");
  await add.click();
  await expect(page.locator("#items > li .item-label")).toHaveText(["Item 4"]);
});

test("a single-row append mounts one row and reconciles nothing (ADR-0098)", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  for (let index = 0; index < 5; index += 1) await add.click();
  await page.evaluate(() => {
    globalThis.standing = [...document.querySelectorAll("#items > li")];
  });
  const before = await regionMetrics(page);
  const beforeTrace = await page.evaluate(() =>
    globalThis.toggleDispose.instrumentation()[7].length);
  await add.click();
  await expect(page.locator("#items > li .item-label"))
    .toHaveText(["Item 0", "Item 1", "Item 2", "Item 3", "Item 4", "Item 5"]);
  // Every standing row keeps the exact DOM node it had: `insertAt` places one
  // new node before the anchor and touches nothing else.
  const retained = await page.evaluate(() =>
    globalThis.standing.every((node, index) =>
      node === document.querySelectorAll("#items > li")[index]));
  expect(retained).toBe(true);
  const after = await regionMetrics(page);
  // [mounts, updates, moves, disposals]: one mount, one placement, and no
  // update at all. The reconcile would have re-run the generated row-update
  // callback on every one of the five standing rows.
  expect(after[0]).toBe(before[0] + 1);
  expect(after[1]).toBe(before[1]);
  expect(after[2]).toBe(before[2] + 1);
  expect(after[3]).toBe(before[3]);
  const trace = await page.evaluate((from) =>
    globalThis.toggleDispose.instrumentation()[7].slice(from), beforeTrace);
  expect(trace.filter((entry) => entry === "region:items:append").length).toBe(1);
  expect(trace.filter((entry) => entry === "region:items:insertAt").length).toBe(1);
  expect(trace.filter((entry) => entry === "region:items:update").length).toBe(0);
  // An append is a structural change however it is recorded, so every sweep
  // the row set can move still ran in the same commit.
  expect(trace.filter((entry) => entry === "count:items:2:evaluated").length).toBe(1);
  expect(trace.filter((entry) => entry === "filter:items:evaluated").length).toBe(1);
  expect(trace.filter((entry) => entry === "storage:items:write").length).toBe(1);
  await expect(page.locator("#items-left")).toHaveText("6 items left of 6");
  // The mounted row is live: its checkbox drives the row's done field
  // through the ordinary ADR-0043 drain.
  const last = page.locator("#items > li").nth(5);
  await last.getByRole("checkbox", { name: "Toggle item" }).check();
  await expect(last).toHaveClass("item-row done");
  await expect(page.locator("#items-left")).toHaveText("5 items left of 6");

  // The contrast, in the same component: the ADR-0050 broadcast re-renders
  // every retained row and keeps the reconcile.
  const beforeAll = await regionMetrics(page);
  await page.getByRole("button", { name: "Complete all" }).click();
  const afterAll = await regionMetrics(page);
  expect(afterAll[0]).toBe(beforeAll[0]);
  expect(afterAll[1]).toBe(beforeAll[1] + 6);
});

test("an append under an active filter takes the sweep's selection (ADR-0098)", async ({ page }) => {
  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await page.locator("#items > li").nth(0).getByRole("checkbox", { name: "Toggle item" }).check();
  await page.getByRole("button", { name: "Show completed" }).click();
  await expect(page.locator("#items > li").nth(0)).toBeVisible();
  await expect(page.locator("#items > li").nth(1)).toBeHidden();
  // The ADR-0051 filter sweep navigates childAt(container, i) by row-table
  // position, so it must run after the drain has put the new row in the host
  // at exactly the position the table holds it. A fresh row is not done, so
  // under "completed" it mounts and is hidden in the same commit.
  await add.click();
  await expect(page.locator("#items > li")).toHaveCount(3);
  await expect(page.locator("#items > li").nth(2)).toBeHidden();
  await expect(page.locator("#items > li").nth(2).locator(".item-label"))
    .toHaveText("Item 2", { useInnerText: false });
  await expect(page.locator("#items-left")).toHaveText("2 items left of 3");
  await page.getByRole("button", { name: "Show all" }).click();
  await expect(page.locator("#items > li").nth(2)).toBeVisible();
  // The stored value carries the appended row, so the write-back woke too.
  const stored = await page.evaluate(() =>
    globalThis.localStorage.getItem("leanrx-toggle-lab.items"));
  expect(stored).toBe("Item 0,Item 0,true,view;Item 1,Item 1,false,view;Item 2,Item 2,false,view");
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
  // TodoMVC's destroy-on-empty-commit — through the same ADR-0097 `removeAt`
  // drain the ✕ button uses.
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
  // its own, and since ADR-0097 it queues no reconcile either — the removal
  // rides `removeAt`, which disposes the dispatching row and leaves the
  // survivor's generated row-update callback unrun. One disposal and nothing
  // else: never a mount, never a move, and now never an update.
  expect(after[0]).toBe(before[0]);
  expect(after[1]).toBe(before[1]);
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
  // same ADR-0097 drain as the raw guard — one disposal and nothing else,
  // never a mount, a move, or a survivor update.
  expect(after[0]).toBe(before[0]);
  expect(after[1]).toBe(before[1]);
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

test("a persisted region's payload is the component's own bytes (ADR-0096)", async ({ page }) => {
  await mountToggle(page);
  // ADR-0096 measured the two segments ADR-0087 left as the floor and found
  // they are not the same kind of cost. The `join` is per *row* (~11.5 ns of
  // segment work, barely byte-sensitive); `storageSet` is per *byte* (~5 us
  // of fixed call cost plus ~0.85 ns per byte, flat in the row count). They
  // looked equal at 35% each only because Toggle Lab's row happens to be
  // about twenty-five bytes. So every byte in this value is paid on every
  // region-touching commit for as long as the region lives, and the two
  // properties that keep those bytes the component's own — one key, and no
  // framing beyond the separators the encoding needs — are pinned here.
  const draft = page.getByRole("textbox", { name: "New todo" });
  await draft.fill("milk, eggs; 100%");
  await draft.press("Enter");
  await page.getByRole("button", { name: "Add item" }).click();
  await page.locator("#items > li").first()
    .getByRole("checkbox", { name: "Toggle item" }).check();

  const observed = await page.evaluate(() => ({
    keys: Object.keys(localStorage).sort(),
    stored: localStorage.getItem("leanrx-toggle-lab.items"),
  }));

  // The fields the two rows carry, escaped the way ADR-0063 seals it. The
  // first row's label exercises all three escapes, so the expansion is
  // counted rather than hidden.
  const escape = (value) =>
    value.split("%").join("%25").split(",").join("%2C").split(";").join("%3B");
  const fields = [
    ["milk, eggs; 100%", "milk, eggs; 100%", "true", "view"],
    ["Item 0", "Item 0", "false", "view"],
  ];
  expect(observed.stored)
    .toBe(fields.map((row) => row.map(escape).join(",")).join(";"));

  // No framing tax: the payload is the escaped fields plus three field
  // separators per row and one row separator between rows, and nothing else.
  // There is no per-row key (hydration reassigns keys from the region's own
  // counter), no position index, no length prefix, no version tag and no
  // chunk header — every one of which a position-keyed or chunked store
  // would want, and every one of which would be charged at ~0.85 ns per byte
  // on every commit forever.
  const payload = fields.reduce(
    (total, row) => total + row.reduce((n, field) => n + escape(field).length, 0),
    0,
  );
  expect(observed.stored.length)
    .toBe(payload + fields.length * 3 + (fields.length - 1));

  // One key per persisted region, and the region's whole table is that one
  // key's value. Splitting it into chunks would make a single-row edit cost
  // one chunk instead of the table, which is the only way left to write
  // fewer bytes per commit; ADR-0096 declines it because a reader in another
  // tab could then observe a torn table between two chunk writes, which is
  // exactly the visibility ADR-0087 contracted away.
  expect(observed.keys).toEqual(["leanrx-toggle-lab.items"]);
});

test("a commit walks a region's row table only when the transaction rebuilt it (ADR-0099)", async ({ page }) => {
  await mountToggle(page);

  // Two instruments, read together. The first is ADR-0088's: a counting
  // `Symbol.iterator` on Array.prototype, installed around one synchronous
  // dispatch and removed before the page gets a turn, which counts only
  // traversals of *this region's row table* — an array whose first element is
  // a seven-cell row tuple `[key, label, draft, done, mode, serial, shown]`
  // behind a numeric key. The second is the emission's own: the ADR-0099
  // `predicate:items:read:` and `filter:items:read:` trace entries, which
  // report how many rows each of those two sweeps actually looked at. The
  // first says "did a loop run", the second says "over how many rows", and a
  // sweep can only be honest about the second if it is honest about the first.
  const probe = (source) =>
    page.evaluate((code) => {
      const original = Array.prototype[Symbol.iterator];
      let counted = 0;
      // `instrumentation()` hands back a copy, so the cursor is a length, not
      // a reference to the live trace.
      const before = globalThis.toggleDispose.instrumentation()[7].length;
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
      return {
        walks: counted,
        reads: globalThis.toggleDispose.instrumentation()[7].slice(before)
          .filter((entry) => entry.includes(":read:")),
      };
    }, source);

  const clickButton = (label) =>
    `Array.from(document.querySelectorAll("button")).find((node) => node.textContent === ${JSON.stringify(label)}).click();`;

  await page.getByRole("button", { name: "Add item" }).click();
  await page.getByRole("button", { name: "Add item" }).click();
  await page.getByRole("button", { name: "Add item" }).click();
  await expect(page.locator("#items > li")).toHaveCount(3);

  // A `toggle` on three rows. Before ADR-0099 this walked three times — the
  // shared predicate pass, the filter sweep and the write-back — for a change
  // that moved one row. The predicate pass is gone: the row event moved the
  // accumulator cells at its own site, so nothing here recomputes them. The
  // filter sweep is still here and still evaluates, but over the *one* row the
  // ADR-0043 pending queue names, and its `hidden` did not move because the
  // filter is `all`. What is left to walk is the write-back, which reads every
  // field of every row and can therefore never narrow.
  expect(await probe('document.querySelectorAll("#items input[type=checkbox]")[0].click();'))
    .toEqual({ walks: 1, reads: ["filter:items:read:1"] });

  // ADR-0084's control, unchanged: `mode` is nothing the filter table reads,
  // so a `dblclick` wakes neither the filter sweep nor — since ADR-0099 — any
  // predicate pass, and the write-back is the commit's only walk. The editing
  // hint still re-evaluates; it just reads a cell instead of a loop.
  expect(await probe('document.querySelectorAll("#items .item-label")[1].dispatchEvent(new MouseEvent("dblclick", { bubbles: true }));'))
    .toEqual({ walks: 1, reads: [] });

  // A keystroke inside the row editor writes `draft`, which nothing but the
  // write-back reads.
  expect(await probe(`
    const editor = document.querySelector("#items input[aria-label='Item editor']");
    editor.value = "typed";
    editor.dispatchEvent(new Event("input", { bubbles: true }));
  `)).toEqual({ walks: 1, reads: [] });
  await page.keyboard.press("Escape");

  // A filter click is the case that keeps the full sweep, and the reason it
  // has to: the selected literal moved, so *every* row's selection can have
  // moved with it, and the sweep says so by reading all three. It touches no
  // region, so the write-back sleeps and no `for`-of runs at all — the sweep
  // walks its rows by index now, which is what makes the narrow path possible.
  expect(await probe(clickButton("Show active")))
    .toEqual({ walks: 0, reads: ["filter:items:read:3"] });
  expect(await probe(clickButton("Show all")))
    .toEqual({ walks: 0, reads: ["filter:items:read:3"] });

  // An append is a structural change that moves one row, and the filter sweep
  // reads exactly it: the ADR-0098 counter says how many rows the table gained
  // and the sweep starts its cursor there. Three walks before ADR-0099, one
  // now, and the one is the write-back.
  expect(await probe(clickButton("Add item")))
    .toEqual({ walks: 1, reads: ["filter:items:read:1"] });

  // A broadcast is the case that keeps everything, and the reason it has to:
  // it writes every row and raises the dirty bit, so the accumulator cells are
  // recomputed from scratch (the rescan, over four rows) and the filter sweep
  // reads all four. Its own write loop is the third walk.
  expect(await probe(clickButton("Complete all")))
    .toEqual({ walks: 3, reads: ["predicate:items:read:4", "filter:items:read:4"] });

  // A removal takes its row out and shifts the survivors, whose selections did
  // not change and whose DOM nodes were never touched — so the filter sweep
  // wakes, finds nothing moved, and reads *zero* rows. The accumulator lost the
  // dropped row's contribution at the splice.
  expect(await probe('document.querySelectorAll("#items button[aria-label=\'Remove item\']")[1].click();'))
    .toEqual({ walks: 1, reads: ["filter:items:read:0"] });

  // The instruments left nothing behind, and every cell still agrees with the
  // DOM: what the accumulator replaces is the traversal, never the answer.
  await expect(page.locator("#items-left strong")).toHaveText("0");
  await expect(page.locator("#toggle-all")).toBeChecked();
  await expect(page.locator("#items > li")).toHaveCount(3);
});

test("the predicate accumulator survives every path that can move a row (ADR-0099)", async ({ page }) => {
  // The accumulator is region state, so a single missed site is a footer that
  // is wrong forever rather than a pixel that is stale for one frame. This
  // walks every path that can move a row — append, toggle, edit-commit,
  // single-row removal, guard-hit removal, broadcast, predicate removal and
  // the ADR-0063 hydration — and after each one checks the three cells against
  // the row table recomputed from scratch, which is what the cells claim to be.
  const agrees = async () => {
    const verdict = await page.evaluate(() => {
      // The truth is read off the DOM, not off the record: the three cells are
      // `done == "false"`, `done == "true"` and `mode == "edit"`, and each of
      // them is visible as a rendered row property.
      const rows = Array.from(document.querySelectorAll("#items > li"));
      const box = (row) => row.querySelector(".item-toggle input");
      const truth = [
        rows.filter((row) => !box(row).checked).length,
        rows.filter((row) => box(row).checked).length,
        rows.filter((row) => row.childNodes[1].firstChild.tagName === "INPUT").length,
      ];
      return {
        truth,
        // Every consumer of a cell, in one read: the `items left` count and
        // its ADR-0062 label (cell 0), the clear-completed button's
        // `hiddenIfEmpty` (cell 1), the toggle-all box's `checkedIfEmpty`
        // (cell 0 again, the shared spelling), and the editing hint (cell 2).
        left: Number(document.querySelector("#items-left strong").textContent),
        toggleAll: document.querySelector("#toggle-all").checked,
        clearHidden: Array.from(document.querySelectorAll("button"))
          .find((node) => node.textContent === "Clear completed").hidden,
        hintHidden: document.querySelector("#edit-hint").hidden,
      };
    });
    expect(verdict.left).toBe(verdict.truth[0]);
    expect(verdict.toggleAll).toBe(verdict.truth[0] === 0);
    expect(verdict.clearHidden).toBe(verdict.truth[1] === 0);
    expect(verdict.hintHidden).toBe(verdict.truth[2] === 0);
    return verdict.truth;
  };

  await mountToggle(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await add.click();
  expect(await agrees()).toEqual([3, 0, 0]);

  await page.locator("#items input[type=checkbox]").first().click();
  expect(await agrees()).toEqual([2, 1, 0]);

  await page.locator("#items > li .item-label").nth(1).dblclick();
  expect(await agrees()).toEqual([2, 1, 1]);

  // A commit with a non-empty draft writes `mode` back to `view`.
  await page.locator("#items input[aria-label='Item editor']").fill("kept");
  await page.locator("#items > li").nth(1).getByRole("button", { name: "Commit item" }).click();
  expect(await agrees()).toEqual([2, 1, 0]);

  // A guard hit: an empty draft turns the same commit into a removal.
  await page.locator("#items > li .item-label").nth(1).dblclick();
  await page.locator("#items input[aria-label='Item editor']").fill("");
  await page.locator("#items > li").nth(1).getByRole("button", { name: "Commit item" }).click();
  expect(await agrees()).toEqual([1, 1, 0]);

  // The sealed single-row removal.
  await page.locator("#items > li").first().getByRole("button", { name: "Remove item" }).click();
  expect(await agrees()).toEqual([1, 0, 0]);

  await add.click();
  await add.click();
  expect(await agrees()).toEqual([3, 0, 0]);

  // The broadcast and the predicate removal both rebuild through the dirty
  // bit, so both are answered by the rescan rather than by a delta.
  await page.getByRole("button", { name: "Complete all" }).click();
  expect(await agrees()).toEqual([0, 3, 0]);
  await page.getByRole("button", { name: "Clear completed" }).click();
  expect(await agrees()).toEqual([0, 0, 0]);

  // Hydration is the last path, and the one with no delta at all: it pushes a
  // whole table and raises the bit.
  await add.click();
  await add.click();
  await page.locator("#items input[type=checkbox]").first().click();
  expect(await agrees()).toEqual([1, 1, 0]);
  await page.reload();
  await page.evaluate(async () => {
    const { mount } = await import("/ToggleLab.mjs");
    globalThis.toggleDispose = mount(document.getElementById("app"));
  });
  await expect(page.locator("#items > li")).toHaveCount(2);
  expect(await agrees()).toEqual([1, 1, 0]);
});

test("every row-table mutation keeps the table key-ordered, and the key search follows it (ADR-0092)", async ({ page }) => {
  // ADR-0092 resolves a dispatching key to its position by binary search, and
  // the search is sound only because the row table is *key-ordered*. That
  // order is not a new invariant — it falls out of contracts already sealed
  // (region-owned keys off a monotone counter, a key slot never written
  // again, order-preserving removals) — so what this gate owes is not "the
  // emission maintains a new structure" but "every mutation the emission can
  // make leaves the old one true, and the search still lands on the right
  // row". One cell per column of the invalidation matrix, in commit order.
  await page.goto(origin);
  await page.evaluate(async () => {
    // Cell 1, hydrate: rows arrive through the append path, so they take
    // consecutive region-owned keys in stored order.
    localStorage.setItem(
      "leanrx-toggle-lab.items",
      "alpha,alpha,false,view;beta,beta,false,view;gamma,gamma,false,view",
    );
    const { mount } = await import("/ToggleLab.mjs");
    globalThis.toggleDispose = mount(document.getElementById("app"));
  });

  // The table's order is observable without reaching into the closure: the
  // reconcile renders rows in table order and ADR-0047's `setKey` stamps each
  // row root with its key, so the DOM row list *is* the table's key sequence.
  const keys = () =>
    page.evaluate(() => Array.from(document.querySelectorAll("#items > li")).map((row) => row.$lrxKey));
  const done = () =>
    page.evaluate(() =>
      Array.from(document.querySelectorAll("#items > li")).map((row) => row.className.includes("done")));
  const ordered = async (cell) => {
    const seen = await keys();
    expect(seen, cell).toEqual([...seen].sort((first, second) => first - second));
    expect(new Set(seen).size, cell).toBe(seen.length);
    return seen;
  };
  // The search itself is witnessed by dispatching on *every* surviving row
  // and demanding that exactly that row moved: a search that resolved a
  // neighbour would flip the wrong class, and one that resolved `-1` would
  // flip nothing. Each row is put back before the next, so the cell leaves
  // the table exactly as it found it.
  const resolvesEveryRow = async (cell) => {
    const before = await done();
    for (let index = 0; index < before.length; index += 1) {
      const box = page.locator("#items > li").nth(index).getByRole("checkbox", { name: "Toggle item" });
      await box.click();
      const after = await done();
      expect(after[index], `${cell}: row ${index} did not move`).toBe(!before[index]);
      expect(after.filter((value, other) => other !== index && value !== before[other]),
        `${cell}: row ${index} moved a neighbour`).toEqual([]);
      await box.click();
      expect(await done(), `${cell}: row ${index} did not restore`).toEqual(before);
    }
  };

  expect(await ordered("hydrate")).toEqual([0, 1, 2]);
  await resolvesEveryRow("hydrate");

  // Cell 2, append: the key counter only ever increases, so an appended row
  // lands last and above every survivor.
  await page.getByRole("button", { name: "Add item" }).click();
  expect(await ordered("append")).toEqual([0, 1, 2, 3]);
  await resolvesEveryRow("append");

  // Cell 3, the ADR-0043 `updateAt` drain: a field write moves no key.
  await page.locator("#items > li").nth(1).getByRole("checkbox", { name: "Toggle item" }).click();
  expect(await ordered("updateAt")).toEqual([0, 1, 2, 3]);
  await page.locator("#items > li").nth(1).getByRole("checkbox", { name: "Toggle item" }).click();

  // Cell 4, the sealed ✕ removal: ADR-0092 splices at the searched position
  // instead of rebuilding the array, and a splice keeps the survivors in
  // their order — so the hole in the key sequence is the only trace of it.
  await page.locator("#items > li").nth(1).getByRole("button", { name: "Remove item" }).click();
  expect(await ordered("remove")).toEqual([0, 2, 3]);
  await resolvesEveryRow("remove");

  // Cell 5, append *after* a removal — the cell the exchange was always owed.
  // A position index would have had to be rebuilt here; the order does not,
  // because the counter never rewinds over the hole.
  await page.getByRole("button", { name: "Add item" }).click();
  expect(await ordered("remove then append")).toEqual([0, 2, 3, 4]);
  await resolvesEveryRow("remove then append");

  // Cell 6, the ADR-0053 guard-hit removal: it splices at the position its
  // own stage already resolved, with no second search.
  await page.locator("#items > li").nth(0).locator(".item-label").dblclick();
  const editor = page.locator("#items > li").nth(0).getByRole("textbox", { name: "Item editor" });
  await editor.fill("   ");
  await editor.press("Enter");
  expect(await ordered("guard-hit removal")).toEqual([2, 3, 4]);
  await resolvesEveryRow("guard-hit removal");

  // Cell 7, the ADR-0050 broadcast: it writes every row's field in place and
  // touches no key.
  await page.getByRole("button", { name: "Complete all" }).click();
  expect(await ordered("broadcast")).toEqual([2, 3, 4]);

  // Cell 8, a filter sweep in the same commit as a drain — the other cell the
  // exchange was owed. `Show active` leaves every done row hidden; untoggling
  // one drains its `updateAt` and re-runs the sweep in that same commit, and
  // the row the search resolved is the row that reappears.
  await page.getByRole("button", { name: "Show active" }).click();
  await expect(page.locator("#items > li:not([hidden])")).toHaveCount(0);
  // The row is hidden, so the click is delivered directly rather than through
  // Playwright's actionability check — the dispatch path is the same
  // delegated listener either way.
  await page.evaluate(() => {
    document.querySelectorAll("#items > li")[1]
      .querySelector("input[type=checkbox]").click();
  });
  expect(await ordered("filter sweep with a drain")).toEqual([2, 3, 4]);
  await expect(page.locator("#items > li:not([hidden])")).toHaveCount(1);
  expect(await page.locator("#items > li:not([hidden])").evaluate((row) => row.$lrxKey)).toBe(3);
  await page.getByRole("button", { name: "Show all" }).click();

  // Cell 9, the ADR-0050 predicate removal: `clearCompleted` still rebuilds
  // the array behind a kept-filter — ADR-0092 left it alone, because a
  // predicate over every row is `O(N)` by contract — and the rebuild is
  // order-preserving, so the invariant survives it too.
  await page.getByRole("button", { name: "Clear completed" }).click();
  expect(await ordered("removeIf")).toEqual([3]);
  await resolvesEveryRow("removeIf");

  // The stored value the whole run persisted agrees with the DOM, so the
  // order the search relied on is the order the write-back saw.
  expect(await page.evaluate(() => localStorage.getItem("leanrx-toggle-lab.items")))
    .toBe("Item 0,Item 0,false,view");
});
