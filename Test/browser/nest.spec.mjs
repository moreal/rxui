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
  "Tick.mjs",
  "Blip.mjs",
  "Chip.mjs",
  "Cuff.mjs",
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
  // ADR-0067: the grandchild mounts inline inside the child, in document
  // order. ADR-0068: its prop is forwarded — Pulse passes its own `title`
  // prop as the grandchild's `label`, so the root-supplied literal shows
  // two levels down.
  await expect(page.locator("#tick-label")).toHaveText("Pulse child");
  await expect(page.locator("#tick-text")).toHaveText("Ticks: 0");
  // ADR-0069: re-forwarding is transitive — Tick forwards the `label` it
  // received into the leaf's `note`, so the root-supplied literal shows
  // three levels down.
  await expect(page.locator("#blip-note")).toHaveText("Pulse child");
  await expect(page.locator("#blip-text")).toHaveText("Blips: 0");
  // ADR-0070: the same received prop fans out into a second leaf, so both
  // leaves render the root-supplied literal. ADR-0071: the same child module
  // composed twice mounts two instances through one import — the forwarded
  // instance renders the root-supplied literal, the repeated instance
  // renders its own sealed literal, and the leaf template uses classes so
  // the instances never collide on a duplicate id.
  await expect(page.locator(".chip-tag")).toHaveText(["Pulse child", "fixed chip"]);
  await expect(page.locator(".chip-text")).toHaveText(["Chips: 0", "Chips: 0"]);
  const pulseOrder = await page.evaluate(() =>
    Array.from(document.querySelector(".pulse").children).map((node) =>
      node.className || node.tagName.toLowerCase(),
    ),
  );
  expect(pulseOrder).toEqual(["h2", "button", "p", "tick"]);
  const tickOrder = await page.evaluate(() =>
    Array.from(document.querySelector(".tick").children).map((node) =>
      node.className || node.tagName.toLowerCase(),
    ),
  );
  expect(tickOrder).toEqual(["h3", "button", "p", "blip", "chip", "chip"]);
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
  await expect(page.locator("#tick-text")).toHaveText("Ticks: 0");
  await page.getByRole("button", { name: "Tick" }).click();
  await expect(page.locator("#tick-text")).toHaveText("Ticks: 1");
  await expect(page.locator("#pulse-text")).toHaveText("Beats: 1");
  await expect(page.locator("#nest-text")).toHaveText("Clicks: 2");
  await page.getByRole("button", { name: "Blip" }).click();
  await expect(page.locator("#blip-text")).toHaveText("Blips: 1");
  await expect(page.locator(".chip-text")).toHaveText(["Chips: 0", "Chips: 0"]);
  await expect(page.locator("#tick-text")).toHaveText("Ticks: 1");
  await expect(page.locator("#pulse-text")).toHaveText("Beats: 1");
  await expect(page.locator("#nest-text")).toHaveText("Clicks: 2");
  // ADR-0070: the fan-out sibling leaves keep fully independent state —
  // clicking one leaf never touches the other. ADR-0071: two instances of
  // the same child module keep fully independent state too — each mount
  // call owns its own state array, so clicking one Chip never touches the
  // other Chip.
  const chipButtons = page.getByRole("button", { name: "Chip" });
  await chipButtons.first().click();
  await chipButtons.first().click();
  await expect(page.locator(".chip-text")).toHaveText(["Chips: 2", "Chips: 0"]);
  await chipButtons.nth(1).click();
  await expect(page.locator(".chip-text")).toHaveText(["Chips: 2", "Chips: 1"]);
  await expect(page.locator("#blip-text")).toHaveText("Blips: 1");
  await expect(page.locator("#tick-text")).toHaveText("Ticks: 1");
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

test("the mark button updates exactly its own row through updateAt", async ({ page }) => {
  await mountNest(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  const before = await page.evaluate(() =>
    globalThis.nestDispose.regionInstrumentation()[0],
  );
  await page.locator("#roster > li").nth(0).getByRole("button", { name: "Mark row" }).click();
  await expect(page.locator("#roster > li .roster-label")).toHaveText([
    "Item 0 ★", "Item 1",
  ]);
  await expect(page.locator("#roster > li").nth(0)).toHaveClass("roster-row marked");
  await expect(page.locator("#roster > li").nth(1)).toHaveClass("roster-row");
  const after = await page.evaluate(() =>
    globalThis.nestDispose.regionInstrumentation()[0],
  );
  // [mounts, updates, moves, disposals]: one mark is exactly one retained-row
  // update (the updateAt path), never a mount, move, or disposal.
  expect(after[0]).toBe(before[0]);
  expect(after[1]).toBe(before[1] + 1);
  expect(after[2]).toBe(before[2]);
  expect(after[3]).toBe(before[3]);
  await page.locator("#roster > li").nth(0).getByRole("button", { name: "Mark row" }).click();
  await expect(page.locator("#roster > li .roster-label")).toHaveText([
    "Item 0 ★ ★", "Item 1",
  ]);
});

test("typing in a row input renames exactly that row through the delegated value payload", async ({ page }) => {
  await mountNest(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  const input = page.locator("#roster > li").nth(0).getByRole("textbox", { name: "Rename row" });
  await input.click();
  const before = await page.evaluate(() =>
    globalThis.nestDispose.regionInstrumentation()[0],
  );
  await input.pressSequentially("abc");
  await expect(page.locator("#roster > li .roster-label")).toHaveText(["abc", "Item 1"]);
  // Each keystroke raises one keydown (record) and one input (rename)
  // transaction; the retained row keeps its identity and its input keeps the
  // typed value, so typing performs retained-row updates only — no mounts,
  // moves, or disposals.
  await expect(page.locator("#roster > li .roster-key").first()).toHaveText("key:c");
  await expect(input).toHaveValue("abc");
  const after = await page.evaluate(() =>
    globalThis.nestDispose.regionInstrumentation()[0],
  );
  expect(after[0]).toBe(before[0]);
  expect(after[1]).toBe(before[1] + 6);
  expect(after[2]).toBe(before[2]);
  expect(after[3]).toBe(before[3]);
});

test("a keydown without input text records only the key payload", async ({ page }) => {
  await mountNest(page);
  await page.getByRole("button", { name: "Add item" }).click();
  const input = page.locator("#roster > li").nth(0).getByRole("textbox", { name: "Rename row" });
  await input.click();
  const before = await page.evaluate(() =>
    globalThis.nestDispose.regionInstrumentation()[0],
  );
  await input.press("Enter");
  await expect(page.locator("#roster > li .roster-key")).toHaveText(["key:Enter"]);
  await expect(page.locator("#roster > li .roster-label")).toHaveText(["Item 0"]);
  const after = await page.evaluate(() =>
    globalThis.nestDispose.regionInstrumentation()[0],
  );
  // Enter fires keydown but no input event: exactly one retained-row update.
  expect(after[1]).toBe(before[1] + 1);
  expect(after[0]).toBe(before[0]);
});

test("renamed and key-stamped rows keep their fields across marking and removal", async ({ page }) => {
  await mountNest(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await add.click();
  const input = page.locator("#roster > li").nth(1).getByRole("textbox", { name: "Rename row" });
  await input.click();
  await input.pressSequentially("renamed");
  await page.locator("#roster > li").nth(1).getByRole("button", { name: "Mark row" }).click();
  await page.locator("#roster > li").nth(0).getByRole("button", { name: "Remove row" }).click();
  await expect(page.locator("#roster > li .roster-label")).toHaveText([
    "renamed ★", "Item 2",
  ]);
  await expect(page.locator("#roster > li .roster-key").first()).toHaveText("key:d");
});

test("marked rows keep their fields across structural reconciles", async ({ page }) => {
  await mountNest(page);
  const add = page.getByRole("button", { name: "Add item" });
  await add.click();
  await add.click();
  await add.click();
  await page.locator("#roster > li").nth(1).getByRole("button", { name: "Mark row" }).click();
  await page.locator("#roster > li").nth(0).getByRole("button", { name: "Remove row" }).click();
  await expect(page.locator("#roster > li .roster-label")).toHaveText([
    "Item 1 ★", "Item 2",
  ]);
  await expect(page.locator("#roster > li").nth(0)).toHaveClass("roster-row marked");
  await add.click();
  await expect(page.locator("#roster > li .roster-label")).toHaveText([
    "Item 1 ★", "Item 2", "Item 3",
  ]);
  await expect(page.locator("#roster > li").nth(0)).toHaveClass("roster-row marked");
  await expect(page.locator("#roster > li").nth(2)).toHaveClass("roster-row");
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
  await expect(page.locator(".tick")).toHaveCount(0);
  await expect(page.locator(".blip")).toHaveCount(0);
  await expect(page.locator(".chip")).toHaveCount(0);
  await expect(page.locator("#roster")).toHaveCount(0);
  const stillAttached = await page.evaluate(() => {
    globalThis.pulseButton.dispatchEvent(new Event("click", { bubbles: true }));
    return document.contains(globalThis.pulseButton);
  });
  expect(stillAttached).toBe(false);
});

test("child instrumentation stays reachable through the parent disposer", async ({ page }) => {
  // ADR-0066: the parent disposer's `children` array republishes each child
  // mount return in declaration order, and parent disposal freezes the
  // child's own counters without erasing that reachability.
  await mountNest(page);
  await page.getByRole("button", { name: "Pulse" }).click();
  await expect(page.locator("#pulse-text")).toHaveText("Beats: 1");
  const before = await page.evaluate(() => {
    const children = globalThis.nestDispose.children;
    return { count: children.length, snapshot: children[0].instrumentation() };
  });
  expect(before.count).toBe(1);
  expect(before.snapshot[7].filter((event) => event === "transaction:commit")).toHaveLength(1);
  await page.evaluate(() => {
    globalThis.pulseButton = document.querySelector(".pulse button");
    globalThis.nestDispose();
  });
  const after = await page.evaluate(() => {
    globalThis.pulseButton.dispatchEvent(new Event("click", { bubbles: true }));
    return globalThis.nestDispose.children[0].instrumentation();
  });
  expect(after).toEqual(before.snapshot);
});

test("grandchild instrumentation composes transitively through children arrays", async ({ page }) => {
  // ADR-0067: the intermediate module republishes its own child through the
  // same ADR-0066 convention, so the grandchild's mount return is reachable
  // from the root disposer as `children[0].children[0]` — and parent
  // disposal removes the grandchild's DOM while freezing its counters
  // without erasing that reachability.
  await mountNest(page);
  await page.getByRole("button", { name: "Tick" }).click();
  await expect(page.locator("#tick-text")).toHaveText("Ticks: 1");
  const before = await page.evaluate(() => {
    const pulse = globalThis.nestDispose.children[0];
    const ticks = pulse.children;
    return {
      count: ticks.length,
      nested: ticks[0] === undefined ? null : typeof ticks[0].instrumentation,
      snapshot: ticks[0].instrumentation(),
      parentTrace: pulse.instrumentation()[7],
    };
  });
  expect(before.count).toBe(1);
  expect(before.nested).toBe("function");
  expect(before.snapshot[7].filter((event) => event === "transaction:commit")).toHaveLength(1);
  // The tick transaction ran in the grandchild's own state array: the
  // intermediate child saw no transaction at all.
  expect(before.parentTrace.filter((event) => event === "transaction:commit")).toHaveLength(0);
  await page.evaluate(() => {
    globalThis.tickButton = document.querySelector(".tick button");
    globalThis.nestDispose();
  });
  const after = await page.evaluate(() => {
    globalThis.tickButton.dispatchEvent(new Event("click", { bubbles: true }));
    return {
      attached: document.contains(globalThis.tickButton),
      snapshot: globalThis.nestDispose.children[0].children[0].instrumentation(),
    };
  });
  expect(after.attached).toBe(false);
  expect(after.snapshot).toEqual(before.snapshot);
});

test("great-grandchild instrumentation stays reachable three levels down", async ({ page }) => {
  // ADR-0069: each level republishes its own children through the ADR-0066
  // convention, so the re-forwarding leaf's mount return is reachable from
  // the root disposer as `children[0].children[0].children[0]` — and root
  // disposal removes the leaf's DOM while freezing its counters without
  // erasing that reachability.
  await mountNest(page);
  await page.getByRole("button", { name: "Blip" }).click();
  await expect(page.locator("#blip-text")).toHaveText("Blips: 1");
  const before = await page.evaluate(() => {
    const tick = globalThis.nestDispose.children[0].children[0];
    const blips = tick.children;
    return {
      count: blips.length,
      nested: blips[0] === undefined ? null : typeof blips[0].instrumentation,
      snapshot: blips[0].instrumentation(),
      parentTrace: tick.instrumentation()[7],
    };
  });
  // ADR-0070/0071: the re-forwarding parent fans out into two leaves and
  // composes the second leaf module twice, so its `children` array carries
  // all three instances in declaration order.
  expect(before.count).toBe(3);
  expect(before.nested).toBe("function");
  expect(before.snapshot[7].filter((event) => event === "transaction:commit")).toHaveLength(1);
  // The blip transaction ran in the leaf's own state array: the re-forwarding
  // intermediate saw no transaction at all.
  expect(before.parentTrace.filter((event) => event === "transaction:commit")).toHaveLength(0);
  await page.evaluate(() => {
    globalThis.blipButton = document.querySelector(".blip button");
    globalThis.nestDispose();
  });
  const after = await page.evaluate(() => {
    globalThis.blipButton.dispatchEvent(new Event("click", { bubbles: true }));
    return {
      attached: document.contains(globalThis.blipButton),
      snapshot:
        globalThis.nestDispose.children[0].children[0].children[0].instrumentation(),
    };
  });
  expect(after.attached).toBe(false);
  expect(after.snapshot).toEqual(before.snapshot);
});

test("fan-out sibling leaves stay independently reachable through the re-forwarding parent", async ({ page }) => {
  // ADR-0070: one receiving component forwards the same received prop into
  // two static children — the disposer's `children` array republishes both
  // mount returns in declaration order, so the sibling leaf is reachable as
  // `children[0].children[0].children[1]`, its transaction commits in its
  // own state array without touching the first leaf, and root disposal
  // freezes both leaves' counters without erasing that reachability.
  // ADR-0071: the same module composed twice mounts two independent
  // instances — the repeated instance is reachable as
  // `children[0].children[0].children[2]`, and its transactions commit in
  // its own state array without touching the first Chip instance.
  await mountNest(page);
  const chipButtons = page.getByRole("button", { name: "Chip" });
  await chipButtons.first().click();
  await chipButtons.nth(1).click();
  await chipButtons.nth(1).click();
  await expect(page.locator(".chip-text")).toHaveText(["Chips: 1", "Chips: 2"]);
  await expect(page.locator("#blip-text")).toHaveText("Blips: 0");
  const before = await page.evaluate(() => {
    const tick = globalThis.nestDispose.children[0].children[0];
    return {
      count: tick.children.length,
      nested: tick.children[2] === undefined
        ? null
        : typeof tick.children[2].instrumentation,
      blipSnapshot: tick.children[0].instrumentation(),
      chipSnapshot: tick.children[1].instrumentation(),
      chip2Snapshot: tick.children[2].instrumentation(),
      parentTrace: tick.instrumentation()[7],
    };
  });
  expect(before.count).toBe(3);
  expect(before.nested).toBe("function");
  // Each instance's transactions ran in its own state array: one commit in
  // the forwarded Chip, two in the repeated Chip, none in the first leaf or
  // the re-forwarding parent.
  expect(before.chipSnapshot[7].filter((event) => event === "transaction:commit")).toHaveLength(1);
  expect(before.chip2Snapshot[7].filter((event) => event === "transaction:commit")).toHaveLength(2);
  expect(before.blipSnapshot[7].filter((event) => event === "transaction:commit")).toHaveLength(0);
  expect(before.parentTrace.filter((event) => event === "transaction:commit")).toHaveLength(0);
  await page.evaluate(() => {
    globalThis.chipButtons = Array.from(document.querySelectorAll(".chip button"));
    globalThis.nestDispose();
  });
  const after = await page.evaluate(() => {
    for (const button of globalThis.chipButtons) {
      button.dispatchEvent(new Event("click", { bubbles: true }));
    }
    const tick = globalThis.nestDispose.children[0].children[0];
    return {
      attachedCount: globalThis.chipButtons.filter((button) =>
        document.contains(button),
      ).length,
      buttonCount: globalThis.chipButtons.length,
      blipSnapshot: tick.children[0].instrumentation(),
      chipSnapshot: tick.children[1].instrumentation(),
      chip2Snapshot: tick.children[2].instrumentation(),
    };
  });
  expect(after.buttonCount).toBe(2);
  expect(after.attachedCount).toBe(0);
  expect(after.chipSnapshot).toEqual(before.chipSnapshot);
  expect(after.chip2Snapshot).toEqual(before.chip2Snapshot);
  expect(after.blipSnapshot).toEqual(before.blipSnapshot);
});

test("each roster row mounts its own chip with a row-mount-constant prop", async ({ page }) => {
  // ADR-0075: the row template composes one child per row, its prop
  // projecting the `origin` row field at row mount — a row-mount constant,
  // legal exactly because no row event or broadcast writes `origin`.
  // ADR-0090: that child is the wrapper `Cuff`, which forwards the constant
  // one level further into its own `Chip`, so the row's chip texts below are
  // read off a *grandchild* of the region.
  await mountNest(page);
  await page.getByRole("button", { name: "Add item" }).click();
  await page.getByRole("button", { name: "Add item" }).click();
  await page.getByRole("button", { name: "Add item" }).click();
  await expect(page.locator("#roster .cuff-mark")).toHaveText([
    "Origin 0", "Origin 1", "Origin 2",
  ]);
  await expect(page.locator("#roster .chip-tag")).toHaveText([
    "Origin 0", "Origin 1", "Origin 2",
  ]);
  // The leaf really is mounted inside the wrapper, not beside it: the row
  // root's last cell is the `.cuff` div and the `.chip` div is its child, so
  // the row opened two templates and the delegated cell math still sees one.
  const rowShape = await page.evaluate(() =>
    Array.from(document.querySelectorAll("#roster > li")).map((row) => [
      Array.from(row.children).map((node) => node.className),
      Array.from(row.querySelector(".cuff").children).map((node) =>
        node.className || node.tagName.toLowerCase(),
      ),
    ]),
  );
  expect(rowShape[0]).toEqual([
    ["roster-label", "roster-key", "roster-edit", "roster-mark", "roster-actions", "cuff"],
    ["cuff-mark", "button", "cuff-text", "chip"],
  ]);
  // Each row's chip owns its own state array — clicking one never touches
  // its row siblings or the view-level chips inside Tick.
  const rowChipButtons = page.locator("#roster .chip button");
  await rowChipButtons.nth(1).click();
  await rowChipButtons.nth(1).click();
  await expect(page.locator("#roster .chip-text")).toHaveText([
    "Chips: 0", "Chips: 2", "Chips: 0",
  ]);
  await expect(page.locator(".tick .chip-text")).toHaveText(["Chips: 0", "Chips: 0"]);
  // A row update (rename, mark) re-renders the row's own text through
  // updateAt but never revisits the child: the prop stays the row-mount
  // constant and the chip's state survives untouched.
  await page.locator("#roster > li").nth(1).getByRole("textbox").fill("Renamed");
  await page.locator("#roster > li").nth(1).getByRole("button", { name: "Mark row" }).click();
  await expect(page.locator("#roster > li .roster-label").nth(1)).toHaveText("Renamed ★");
  await expect(page.locator("#roster .chip-tag")).toHaveText([
    "Origin 0", "Origin 1", "Origin 2",
  ]);
  await expect(page.locator("#roster .chip-text").nth(1)).toHaveText("Chips: 2");
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("a row-composed wrapper mounts and disposes its own leaf per row", async ({ page }) => {
  // ADR-0090: the row child is a wrapper, so each row opens two templates and
  // the inventory entry is one hop above the leaf — the per-row grandchild is
  // reachable as `children[1 + i].children[0]`, commits in its own state
  // array, and rides its wrapper's disposal on row removal. This is the shape
  // `LRX-ELAB-135` now has to answer about: the row lowering saw only the name
  // `Cuff`, and `Chip` is a string inside `Cuff`'s child table.
  await mountNest(page);
  await page.getByRole("button", { name: "Add item" }).click();
  await page.getByRole("button", { name: "Add item" }).click();
  await expect(page.locator("#roster > li")).toHaveCount(2);
  const cuffButtons = page.locator("#roster .cuff > button");
  await cuffButtons.first().click();
  await page.locator("#roster .chip button").nth(1).click();
  await page.locator("#roster .chip button").nth(1).click();
  await expect(page.locator("#roster .cuff-text")).toHaveText(["Cuffs: 1", "Cuffs: 0"]);
  await expect(page.locator("#roster .chip-text")).toHaveText(["Chips: 0", "Chips: 2"]);
  // The wrapper and its leaf keep separate state arrays: neither click shows
  // up in the other's trace, and neither reaches the region or the parent.
  const reach = await page.evaluate(() => {
    const inventory = globalThis.nestDispose.children;
    const wrapper = inventory[1];
    const leaf = wrapper.children[0];
    return {
      inventoryCount: inventory.length,
      leafKind: typeof leaf.instrumentation,
      wrapperCommits: wrapper.instrumentation()[7]
        .filter((event) => event === "transaction:commit").length,
      leafCommits: leaf.instrumentation()[7]
        .filter((event) => event === "transaction:commit").length,
      secondLeafCommits: inventory[2].children[0].instrumentation()[7]
        .filter((event) => event === "transaction:commit").length,
    };
  });
  // Two rows, two inventory entries behind the static Pulse seed — the leaves
  // never join the inventory, they hang off their own wrapper's disposer.
  expect(reach.inventoryCount).toBe(3);
  expect(reach.leafKind).toBe("function");
  expect(reach.wrapperCommits).toBe(1);
  expect(reach.leafCommits).toBe(0);
  expect(reach.secondLeafCommits).toBe(2);
  // Removing the row disposes the wrapper, which disposes its leaf: both
  // freeze, and the leaf's DOM leaves with the row.
  const frozen = await page.evaluate(() => {
    globalThis.rowWrapper = globalThis.nestDispose.children[1];
    globalThis.rowLeaf = globalThis.rowWrapper.children[0];
    globalThis.rowLeafButton = document.querySelector("#roster .chip button");
    return {
      wrapper: globalThis.rowWrapper.instrumentation(),
      leaf: globalThis.rowLeaf.instrumentation(),
    };
  });
  await page.locator("#roster > li").first().getByRole("button", { name: "Remove row" }).click();
  await expect(page.locator("#roster > li")).toHaveCount(1);
  const after = await page.evaluate(() => {
    globalThis.rowLeafButton.dispatchEvent(new Event("click", { bubbles: true }));
    return {
      count: globalThis.nestDispose.children.length,
      stillListed: globalThis.nestDispose.children.includes(globalThis.rowWrapper),
      attached: document.contains(globalThis.rowLeafButton),
      wrapper: globalThis.rowWrapper.instrumentation(),
      leaf: globalThis.rowLeaf.instrumentation(),
    };
  });
  expect(after.count).toBe(2);
  expect(after.stillListed).toBe(false);
  expect(after.attached).toBe(false);
  expect(after.wrapper).toEqual(frozen.wrapper);
  expect(after.leaf).toEqual(frozen.leaf);
  // The surviving row keeps both of its levels live and untouched.
  await expect(page.locator("#roster .cuff-mark")).toHaveText(["Origin 1"]);
  await expect(page.locator("#roster .chip-text")).toHaveText(["Chips: 2"]);
  await page.locator("#roster .chip button").click();
  await expect(page.locator("#roster .chip-text")).toHaveText(["Chips: 3"]);
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("the live children inventory tracks row mounts and removals", async ({ page }) => {
  // ADR-0075: `disposer.children` republishes the shared live inventory —
  // the static Pulse disposer seeded first, then one entry per mounted row
  // in mount order, spliced as rows leave.
  await mountNest(page);
  const seeded = await page.evaluate(() => globalThis.nestDispose.children.length);
  expect(seeded).toBe(1);
  await page.getByRole("button", { name: "Add item" }).click();
  await page.getByRole("button", { name: "Add item" }).click();
  await expect(page.locator("#roster > li")).toHaveCount(2);
  const mounted = await page.evaluate(() => {
    const children = globalThis.nestDispose.children;
    return {
      count: children.length,
      rowChildKind: typeof children[1].instrumentation,
    };
  });
  expect(mounted.count).toBe(3);
  expect(mounted.rowChildKind).toBe("function");
  // Removing the first row splices its entry out of the inventory and
  // disposes it: the DOM leaves with the row, the captured disposer stays
  // reachable with frozen counters, and the retained row keeps its child
  // instance (and state) across the structural reconcile.
  await page.locator("#roster .chip button").nth(1).click();
  await page.evaluate(() => {
    globalThis.firstRowChild = globalThis.nestDispose.children[1];
    globalThis.firstRowChipButton = document.querySelectorAll("#roster .chip button")[0];
  });
  await page.locator("#roster > li").first().getByRole("button", { name: "Remove row" }).click();
  await expect(page.locator("#roster > li")).toHaveCount(1);
  await expect(page.locator("#roster .chip-tag")).toHaveText(["Origin 1"]);
  await expect(page.locator("#roster .chip-text")).toHaveText(["Chips: 1"]);
  const removed = await page.evaluate(() => {
    globalThis.firstRowChipButton.dispatchEvent(new Event("click", { bubbles: true }));
    return {
      count: globalThis.nestDispose.children.length,
      stillListed: globalThis.nestDispose.children.includes(globalThis.firstRowChild),
      attached: document.contains(globalThis.firstRowChipButton),
      snapshot: globalThis.firstRowChild.instrumentation(),
    };
  });
  expect(removed.count).toBe(2);
  expect(removed.stillListed).toBe(false);
  expect(removed.attached).toBe(false);
  expect(removed.snapshot[7].filter((event) => event === "transaction:commit")).toHaveLength(0);
  // A fresh append mounts a fresh child with fresh state behind the retained
  // row's entry.
  await page.getByRole("button", { name: "Add item" }).click();
  await expect(page.locator("#roster .chip-tag")).toHaveText(["Origin 1", "Origin 2"]);
  await expect(page.locator("#roster .chip-text")).toHaveText(["Chips: 1", "Chips: 0"]);
  const readded = await page.evaluate(() => globalThis.nestDispose.children.length);
  expect(readded).toBe(3);
});

test("root disposal disposes row chips while the inventory keeps reachability", async ({ page }) => {
  // ADR-0075: the region's own dispose path passes no context, so the
  // inventory keeps its entries exactly as the static ADR-0066 array does —
  // every entry disposed, counters frozen, DOM gone. ADR-0090: the frozen
  // counter read below belongs to the per-row *grandchild*, one hop behind
  // the inventory entry, so root disposal reaches through the wrapper.
  await mountNest(page);
  await page.getByRole("button", { name: "Add item" }).click();
  await page.getByRole("button", { name: "Add item" }).click();
  await page.locator("#roster .chip button").first().click();
  await expect(page.locator("#roster .chip-text").first()).toHaveText("Chips: 1");
  const before = await page.evaluate(() => {
    globalThis.rowChipButtons = Array.from(
      document.querySelectorAll("#roster .chip button"),
    );
    const snapshot = globalThis.nestDispose.children[1].children[0].instrumentation();
    globalThis.nestDispose();
    return snapshot;
  });
  const after = await page.evaluate(() => {
    for (const button of globalThis.rowChipButtons) {
      button.dispatchEvent(new Event("click", { bubbles: true }));
    }
    return {
      count: globalThis.nestDispose.children.length,
      attachedCount: globalThis.rowChipButtons.filter((button) =>
        document.contains(button),
      ).length,
      snapshot: globalThis.nestDispose.children[1].children[0].instrumentation(),
    };
  });
  expect(after.count).toBe(3);
  expect(after.attachedCount).toBe(0);
  expect(after.snapshot).toEqual(before);
});
