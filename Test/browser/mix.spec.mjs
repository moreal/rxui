import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_MIX_DIST;
if (!directory) throw new Error("LEANRX_MIX_DIST is required");

const files = new Set([
  "MixLab.mjs",
  "Badge.mjs",
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
        response.end("<!doctype html><html lang=\"en\"><head><title>Mix Lab</title></head><body><div id=\"app\"></div></body></html>");
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

async function mountMix(page) {
  await page.goto(origin);
  await page.evaluate(async () => {
    const { mount } = await import("/MixLab.mjs");
    globalThis.mixDispose = mount(document.getElementById("app"));
  });
}

test("the combined region mounts empty with the static badge seeded first", async ({ page }) => {
  await mountMix(page);
  await expect(page.locator("#crew-line")).toHaveText("0 done of 0");
  await expect(page.locator("#crew")).toBeHidden();
  await expect(page.getByRole("button", { name: "Clear done" })).toBeHidden();
  await expect(page.locator(".badge-tag")).toHaveText(["static badge"]);
  const seeded = await page.evaluate(() => globalThis.mixDispose.children.length);
  expect(seeded).toBe(1);
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("appended rows mount badges, and badge clicks touch no region state", async ({ page }) => {
  await mountMix(page);
  const add = page.getByRole("button", { name: "Add member" });
  await add.click();
  await add.click();
  await expect(page.locator("#crew > li .crew-label")).toHaveText([
    "Member 0", "Member 1",
  ]);
  await expect(page.locator("#crew .badge-tag")).toHaveText(["Tag 0", "Tag 1"]);
  await expect(page.locator("#crew-line")).toHaveText("0 done of 2");
  const mounted = await page.evaluate(() => globalThis.mixDispose.children.length);
  expect(mounted).toBe(3);
  // ADR-0076: counts, the persisted value, and the region metrics are
  // row-table-scoped — a Badge transaction commits in the child's own state
  // array and touches none of them.
  const before = await page.evaluate(() => ({
    metrics: globalThis.mixDispose.regionInstrumentation()[0],
    stored: localStorage.getItem("leanrx-mix-lab.crew"),
  }));
  await page.locator("#crew .badge button").first().click();
  await page.locator("#crew .badge button").first().click();
  await expect(page.locator("#crew .badge-text")).toHaveText(["Hits: 2", "Hits: 0"]);
  await expect(page.locator("#crew-line")).toHaveText("0 done of 2");
  const after = await page.evaluate(() => ({
    metrics: globalThis.mixDispose.regionInstrumentation()[0],
    stored: localStorage.getItem("leanrx-mix-lab.crew"),
  }));
  expect(after.metrics).toEqual(before.metrics);
  expect(after.stored).toBe(before.stored);
  expect(after.stored).toBe("Member 0,false,Tag 0;Member 1,false,Tag 1");
});

test("hydrated rows mount their badges through the shared reconcile", async ({ page }) => {
  // ADR-0076: hydration rides the ordinary dirty-flag commit, whose reconcile
  // forwards the inventory slot as the child context — hydrated rows are full
  // citizens of the row-child vocabulary.
  await page.goto(origin);
  await page.evaluate(async () => {
    localStorage.setItem("leanrx-mix-lab.crew", "Alpha,true,Tag A;Beta,false,Tag B");
    const { mount } = await import("/MixLab.mjs");
    globalThis.mixDispose = mount(document.getElementById("app"));
  });
  await expect(page.locator("#crew > li .crew-label")).toHaveText(["Alpha", "Beta"]);
  await expect(page.locator("#crew .badge-tag")).toHaveText(["Tag A", "Tag B"]);
  await expect(page.locator("#crew > li").first()).toHaveClass("crew-row done");
  await expect(page.locator("#crew > li").first()
    .getByRole("checkbox", { name: "Toggle member" })).toBeChecked();
  await expect(page.locator("#crew-line")).toHaveText("1 done of 2");
  await expect(page.locator("#crew")).toBeVisible();
  const hydrated = await page.evaluate(() => ({
    count: globalThis.mixDispose.children.length,
    rowChildKind: typeof globalThis.mixDispose.children[1].instrumentation,
    trace: globalThis.mixDispose.instrumentation()[7],
  }));
  expect(hydrated.count).toBe(3);
  expect(hydrated.rowChildKind).toBe("function");
  expect(hydrated.trace).toContain("event:hydrate:crew");
  expect(hydrated.trace).toContain("region:crew:hydrate");
  expect(hydrated.trace).toContain("storage:crew:write");
  // Hydrated badges are live instances with their own state.
  await page.locator("#crew .badge button").nth(1).click();
  await expect(page.locator("#crew .badge-text")).toHaveText(["Hits: 0", "Hits: 1"]);
});

test("filtering hides row roots without disposing or muting their badges", async ({ page }) => {
  await mountMix(page);
  const add = page.getByRole("button", { name: "Add member" });
  await add.click();
  await add.click();
  await page.locator("#crew > li").first()
    .getByRole("checkbox", { name: "Toggle member" }).check();
  await expect(page.locator("#crew-line")).toHaveText("1 done of 2");
  await page.locator("#crew .badge button").first().click();
  await expect(page.locator("#crew .badge-text").first()).toHaveText("Hits: 1");
  const before = await page.evaluate(() => ({
    metrics: globalThis.mixDispose.regionInstrumentation()[0],
    count: globalThis.mixDispose.children.length,
  }));
  // ADR-0076: the filter sweep writes `hidden` on row roots by container
  // index — the Badge lives inside the row root, so the row hides as one
  // unit and the child is neither disposed nor spliced.
  await page.getByRole("button", { name: "Show active" }).click();
  await expect(page.locator("#crew > li").first()).toBeHidden();
  await expect(page.locator("#crew > li").nth(1)).toBeVisible();
  const hidden = await page.evaluate(() => ({
    metrics: globalThis.mixDispose.regionInstrumentation()[0],
    count: globalThis.mixDispose.children.length,
    badgeAttached: document.contains(document.querySelectorAll("#crew .badge")[0]),
  }));
  expect(hidden.metrics).toEqual(before.metrics);
  expect(hidden.count).toBe(before.count);
  expect(hidden.badgeAttached).toBe(true);
  // Unhiding restores the same row and the same badge instance — state
  // intact, no mounts, no disposals.
  await page.getByRole("button", { name: "Show all" }).click();
  await expect(page.locator("#crew > li").first()).toBeVisible();
  await expect(page.locator("#crew .badge-text").first()).toHaveText("Hits: 1");
  const restored = await page.evaluate(() =>
    globalThis.mixDispose.regionInstrumentation()[0],
  );
  expect(restored).toEqual(before.metrics);
});

test("a removal decrements the counts and splices the inventory in one commit", async ({ page }) => {
  await mountMix(page);
  const add = page.getByRole("button", { name: "Add member" });
  await add.click();
  await add.click();
  await add.click();
  await page.locator("#crew .badge button").first().click();
  await expect(page.locator("#crew-line")).toHaveText("0 done of 3");
  await page.evaluate(() => {
    globalThis.firstRowBadge = globalThis.mixDispose.children[1];
    globalThis.firstRowBadgeButton = document.querySelectorAll("#crew .badge button")[0];
  });
  await page.locator("#crew > li").first()
    .getByRole("button", { name: "Remove member" }).click();
  await expect(page.locator("#crew-line")).toHaveText("0 done of 2");
  await expect(page.locator("#crew .badge-tag")).toHaveText(["Tag 1", "Tag 2"]);
  const removed = await page.evaluate(() => {
    globalThis.firstRowBadgeButton.dispatchEvent(new Event("click", { bubbles: true }));
    return {
      count: globalThis.mixDispose.children.length,
      stillListed: globalThis.mixDispose.children.includes(globalThis.firstRowBadge),
      attached: document.contains(globalThis.firstRowBadgeButton),
      snapshot: globalThis.firstRowBadge.instrumentation(),
      stored: localStorage.getItem("leanrx-mix-lab.crew"),
    };
  });
  expect(removed.count).toBe(3);
  expect(removed.stillListed).toBe(false);
  expect(removed.attached).toBe(false);
  expect(removed.snapshot[7].filter((event) => event === "transaction:commit")).toHaveLength(1);
  expect(removed.stored).toBe("Member 1,false,Tag 1;Member 2,false,Tag 2");
  // The predicate removal path splices through the same dispose callback:
  // clearing the done rows drops their badges from the inventory too.
  await page.locator("#crew > li").first()
    .getByRole("checkbox", { name: "Toggle member" }).check();
  await expect(page.locator("#crew-line")).toHaveText("1 done of 2");
  await page.getByRole("button", { name: "Clear done" }).click();
  await expect(page.locator("#crew-line")).toHaveText("0 done of 1");
  await expect(page.locator("#crew .badge-tag")).toHaveText(["Tag 2"]);
  const cleared = await page.evaluate(() => ({
    count: globalThis.mixDispose.children.length,
    stored: localStorage.getItem("leanrx-mix-lab.crew"),
  }));
  expect(cleared.count).toBe(2);
  expect(cleared.stored).toBe("Member 2,false,Tag 2");
});

test("root disposal disposes row badges while the inventory keeps reachability", async ({ page }) => {
  await mountMix(page);
  const add = page.getByRole("button", { name: "Add member" });
  await add.click();
  await add.click();
  await page.locator("#crew .badge button").first().click();
  const before = await page.evaluate(() => {
    globalThis.rowBadgeButtons = Array.from(
      document.querySelectorAll("#crew .badge button"),
    );
    const snapshot = globalThis.mixDispose.children[1].instrumentation();
    globalThis.mixDispose();
    return snapshot;
  });
  const after = await page.evaluate(() => {
    for (const button of globalThis.rowBadgeButtons) {
      button.dispatchEvent(new Event("click", { bubbles: true }));
    }
    return {
      count: globalThis.mixDispose.children.length,
      attachedCount: globalThis.rowBadgeButtons.filter((button) =>
        document.contains(button),
      ).length,
      snapshot: globalThis.mixDispose.children[1].instrumentation(),
    };
  });
  expect(after.count).toBe(3);
  expect(after.attachedCount).toBe(0);
  expect(after.snapshot).toEqual(before);
});
