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
  // order, with its own literal prop riding the nested mount call.
  await expect(page.locator("#tick-label")).toHaveText("Tick child");
  await expect(page.locator("#tick-text")).toHaveText("Ticks: 0");
  const pulseOrder = await page.evaluate(() =>
    Array.from(document.querySelector(".pulse").children).map((node) =>
      node.className || node.tagName.toLowerCase(),
    ),
  );
  expect(pulseOrder).toEqual(["h2", "button", "p", "tick"]);
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
