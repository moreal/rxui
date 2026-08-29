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
  "Stamp.mjs",
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
  // ADR-0078: the second region owns its own count cell and its own
  // emptiness selection — attr 2 in document order, behind crew's attrs 0
  // and 1, driven by pins' own touched flag.
  await expect(page.locator("#pins-line")).toHaveText("0 pinned");
  await expect(page.locator("#pins")).toBeHidden();
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
  // ADR-0089: each crew row also mounts the repeated Stamp pair — the
  // projected `label` and the literal — so the shared inventory grows by
  // three per row, not one.
  await expect(page.locator("#crew .stamp-mark")).toHaveText([
    "Member 0", "crew stamp", "Member 1", "crew stamp",
  ]);
  await expect(page.locator("#crew-line")).toHaveText("0 done of 2");
  const mounted = await page.evaluate(() => globalThis.mixDispose.children.length);
  expect(mounted).toBe(7);
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
  await expect(page.locator("#crew .stamp-mark")).toHaveText([
    "Alpha", "crew stamp", "Beta", "crew stamp",
  ]);
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
  expect(hydrated.count).toBe(7);
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
  expect(removed.count).toBe(7);
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
  expect(cleared.count).toBe(4);
  expect(cleared.stored).toBe("Member 2,false,Tag 2");
});

test("a broadcast re-renders retained rows without remounting or muting their badges", async ({ page }) => {
  await mountMix(page);
  const add = page.getByRole("button", { name: "Add member" });
  await add.click();
  await add.click();
  await page.locator("#crew .badge button").first().click();
  await expect(page.locator("#crew .badge-text").first()).toHaveText("Hits: 1");
  const before = await page.evaluate(() => ({
    entries: (globalThis.mixEntries = globalThis.mixDispose.children.slice()).length,
    metrics: globalThis.mixDispose.regionInstrumentation()[0],
  }));
  // ADR-0077: the broadcast writes every row's `done` in place and rides the
  // dirty reconcile — every key is retained, so rows re-render through the
  // update callback and no row child is remounted, disposed, or reset.
  await page.getByRole("button", { name: "Mark all done" }).click();
  await expect(page.locator("#crew-line")).toHaveText("2 done of 2");
  await expect(page.locator("#crew > li").first()).toHaveClass("crew-row done");
  await expect(page.locator("#crew > li").nth(1)).toHaveClass("crew-row done");
  await expect(page.locator("#crew > li").first()
    .getByRole("checkbox", { name: "Toggle member" })).toBeChecked();
  await expect(page.locator("#crew .badge-text")).toHaveText(["Hits: 1", "Hits: 0"]);
  const after = await page.evaluate(() => ({
    count: globalThis.mixDispose.children.length,
    identical: globalThis.mixDispose.children.every(
      (child, index) => child === globalThis.mixEntries[index],
    ),
    metrics: globalThis.mixDispose.regionInstrumentation()[0],
    trace: globalThis.mixDispose.instrumentation()[7],
    stored: localStorage.getItem("leanrx-mix-lab.crew"),
  }));
  expect(after.count).toBe(before.entries);
  expect(after.identical).toBe(true);
  expect(after.metrics[0]).toBe(before.metrics[0]);
  expect(after.metrics[3]).toBe(before.metrics[3]);
  expect(after.metrics[1]).toBe(before.metrics[1] + 2);
  expect(after.trace).toContain("region:crew:broadcast");
  expect(after.stored).toBe("Member 0,true,Tag 0;Member 1,true,Tag 1");
  // The retained badge is still the same live instance.
  await page.locator("#crew .badge button").first().click();
  await expect(page.locator("#crew .badge-text").first()).toHaveText("Hits: 2");
});

test("a three-child row splices exactly its own run and keeps the survivors live", async ({ page }) => {
  await mountMix(page);
  const add = page.getByRole("button", { name: "Add member" });
  await add.click();
  await add.click();
  await add.click();
  // ADR-0089: one row mounts three children in template order — a Badge and
  // the same Stamp twice, the repeat through one aliased import with its own
  // props — so the shared inventory is the static seed followed by one
  // contiguous run of three per row.
  await expect(
    page.locator("#crew > li").first().locator(".badge-tag, .stamp-mark"),
  ).toHaveText(["Tag 0", "Member 0", "crew stamp"]);
  const middle = page.locator("#crew > li").nth(1);
  await middle.locator(".badge button").click();
  await middle.locator(".stamp button").first().click();
  await middle.locator(".stamp button").nth(1).click();
  await middle.locator(".stamp button").nth(1).click();
  await expect(middle.locator(".badge-text")).toHaveText("Hits: 1");
  await expect(middle.locator(".stamp-text")).toHaveText(["Stamps: 1", "Stamps: 2"]);
  const seeded = await page.evaluate(() => {
    globalThis.mixEntries = globalThis.mixDispose.children.slice();
    globalThis.middleButtons = Array.from(
      document.querySelectorAll("#crew > li")[1]
        .querySelectorAll(".badge button, .stamp button"),
    );
    globalThis.middleChildren = globalThis.mixEntries.slice(4, 7);
    return {
      count: globalThis.mixEntries.length,
      commits: globalThis.middleChildren.map((child) => child.instrumentation()[1]),
    };
  });
  expect(seeded.count).toBe(10);
  // The repeated pair are separate instances: one import, three independent
  // states, told apart here by their own commit counts.
  expect(seeded.commits).toEqual([1, 1, 2]);
  // Removing the middle row splices exactly its own run of three — the runs
  // on either side keep both their identities and their order, because each
  // entry leaves by its own function identity, never by position.
  await middle.getByRole("button", { name: "Remove member" }).click();
  await expect(page.locator("#crew > li .crew-label")).toHaveText([
    "Member 0", "Member 2",
  ]);
  const removed = await page.evaluate(() => {
    for (const button of globalThis.middleButtons) {
      button.dispatchEvent(new Event("click", { bubbles: true }));
    }
    return {
      order: globalThis.mixDispose.children.map((child) =>
        globalThis.mixEntries.indexOf(child),
      ),
      attached: globalThis.middleButtons.filter((button) =>
        document.contains(button),
      ).length,
      commits: globalThis.middleChildren.map((child) => child.instrumentation()[1]),
    };
  });
  expect(removed.order).toEqual([0, 1, 2, 3, 7, 8, 9]);
  expect(removed.attached).toBe(0);
  // All three were disposed, not just the first: every listener is gone, so
  // the dispatched clicks commit nothing.
  expect(removed.commits).toEqual([1, 1, 2]);
  // ADR-0077: a broadcast retains every key, so the reconcile re-renders the
  // survivors without touching a single inventory entry.
  await page.getByRole("button", { name: "Mark all done" }).click();
  await expect(page.locator("#crew-line")).toHaveText("2 done of 2");
  const broadcast = await page.evaluate(() =>
    globalThis.mixDispose.children.map((child) =>
      globalThis.mixEntries.indexOf(child),
    ),
  );
  expect(broadcast).toEqual([0, 1, 2, 3, 7, 8, 9]);
  // And the next reconcile appends the new row's whole run behind them.
  await add.click();
  const appended = await page.evaluate(() => ({
    order: globalThis.mixDispose.children.slice(0, 7).map((child) =>
      globalThis.mixEntries.indexOf(child),
    ),
    count: globalThis.mixDispose.children.length,
    marks: Array.from(
      document.querySelectorAll("#crew > li:last-child .stamp-mark"),
      (node) => node.textContent,
    ),
  }));
  expect(appended.order).toEqual([0, 1, 2, 3, 7, 8, 9]);
  expect(appended.count).toBe(10);
  expect(appended.marks).toEqual(["Member 3", "crew stamp"]);
  // The survivors are still live instances carrying their own state.
  await page.locator("#crew > li").first().locator(".stamp button").first().click();
  await expect(
    page.locator("#crew > li").first().locator(".stamp-text").first(),
  ).toHaveText("Stamps: 1");
});

test("two child-composing regions interleave the shared inventory in mount order", async ({ page }) => {
  await mountMix(page);
  // ADR-0077: one mount-scope inventory — the static seed first, then row
  // entries in actual mount order across both regions, not grouped by region.
  await page.getByRole("button", { name: "Add pin" }).click();
  await page.getByRole("button", { name: "Add member" }).click();
  await page.getByRole("button", { name: "Add pin" }).click();
  await expect(page.locator("#pins .badge-tag")).toHaveText(["Pin 0", "Pin 2"]);
  await expect(page.locator("#crew .badge-tag")).toHaveText(["Tag 1"]);
  await expect(page.locator("#pins .pin-note")).toHaveText(["Pin 0", "Pin 2"]);
  await page.locator("#pins .badge button").first().click();
  await page.locator("#crew .badge button").first().click();
  await page.locator("#crew .badge button").first().click();
  // ADR-0089: the crew row contributes a run of three, so the interleaving
  // is by *entry*, not by row — the crew Stamp pair sits between the two
  // pins' single entries, in the crew template's own mount order.
  for (let index = 0; index < 3; index += 1) {
    await page.locator("#crew .stamp button").first().click();
  }
  for (let index = 0; index < 4; index += 1) {
    await page.locator("#crew .stamp button").nth(1).click();
  }
  for (let index = 0; index < 5; index += 1) {
    await page.locator("#pins .badge button").nth(1).click();
  }
  await expect(page.locator("#pins .badge-text")).toHaveText(["Hits: 1", "Hits: 5"]);
  await expect(page.locator("#crew .badge-text")).toHaveText(["Hits: 2"]);
  await expect(page.locator("#crew .stamp-text")).toHaveText([
    "Stamps: 3", "Stamps: 4",
  ]);
  const commits = await page.evaluate(() =>
    globalThis.mixDispose.children.map((child) =>
      child.instrumentation()[7].filter((event) => event === "transaction:commit").length,
    ),
  );
  // Inventory order = [static, first pin, crew badge, crew stamp, crew stamp,
  // second pin] — pinned by each child's own commit count.
  expect(commits).toEqual([0, 1, 2, 3, 4, 5]);
});

test("a removal in one region splices only its own inventory entry", async ({ page }) => {
  await mountMix(page);
  await page.getByRole("button", { name: "Add pin" }).click();
  await page.getByRole("button", { name: "Add member" }).click();
  await page.getByRole("button", { name: "Add pin" }).click();
  const seeded = await page.evaluate(() => {
    globalThis.mixEntries = globalThis.mixDispose.children.slice();
    return {
      count: globalThis.mixEntries.length,
      crewMetrics: globalThis.mixDispose.regionInstrumentation()[0],
    };
  });
  expect(seeded.count).toBe(6);
  // ADR-0077: each dispose callback splices by indexOf of its own row's
  // stashed mount return — removing a pin leaves the crew entry (and the
  // other pin) exactly in place, and the crew region's metrics untouched.
  await page.locator("#pins > li").first()
    .getByRole("button", { name: "Remove pin" }).click();
  const pinRemoved = await page.evaluate(() => ({
    children: globalThis.mixDispose.children.map((child) =>
      globalThis.mixEntries.indexOf(child),
    ),
    crewMetrics: globalThis.mixDispose.regionInstrumentation()[0],
    pinDisposals: globalThis.mixDispose.regionInstrumentation()[1][3],
  }));
  expect(pinRemoved.children).toEqual([0, 2, 3, 4, 5]);
  expect(pinRemoved.crewMetrics).toEqual(seeded.crewMetrics);
  expect(pinRemoved.pinDisposals).toBe(1);
  await expect(page.locator("#crew .badge-tag")).toHaveText(["Tag 1"]);
  await expect(page.locator("#pins .badge-tag")).toHaveText(["Pin 2"]);
  // And the mirror image: removing the crew row leaves both pins' entries.
  await page.locator("#crew > li").first()
    .getByRole("button", { name: "Remove member" }).click();
  const crewRemoved = await page.evaluate(() => ({
    children: globalThis.mixDispose.children.map((child) =>
      globalThis.mixEntries.indexOf(child),
    ),
    pinMetrics: globalThis.mixDispose.regionInstrumentation()[1],
  }));
  // The crew row's whole run of three leaves at once, the surviving pin's
  // single entry keeps its identity and its place.
  expect(crewRemoved.children).toEqual([0, 5]);
  expect(crewRemoved.pinMetrics[3]).toBe(1);
  await expect(page.locator("#pins .badge-tag")).toHaveText(["Pin 2"]);
});

test("two persisted regions hydrate and save under their own keys", async ({ page }) => {
  // ADR-0078: one persist item per region, each with its own sealed key —
  // mount runs one hydrate transaction per persisted region in declaration
  // order, and each region's write-back rides its own touched flag.
  await page.goto(origin);
  await page.evaluate(async () => {
    localStorage.setItem("leanrx-mix-lab.crew", "Alpha,true,Tag A");
    localStorage.setItem("leanrx-mix-lab.pins", "Pin A;Pin B");
    const { mount } = await import("/MixLab.mjs");
    globalThis.mixDispose = mount(document.getElementById("app"));
  });
  await expect(page.locator("#crew > li .crew-label")).toHaveText(["Alpha"]);
  await expect(page.locator("#pins .pin-note")).toHaveText(["Pin A", "Pin B"]);
  await expect(page.locator("#crew-line")).toHaveText("1 done of 1");
  await expect(page.locator("#pins-line")).toHaveText("2 pinned");
  await expect(page.locator("#crew")).toBeVisible();
  await expect(page.locator("#pins")).toBeVisible();
  const hydrated = await page.evaluate(() => ({
    count: globalThis.mixDispose.children.length,
    trace: globalThis.mixDispose.instrumentation()[7],
    tags: Array.from(document.querySelectorAll(".badge-tag"), (node) => node.textContent),
    marks: Array.from(document.querySelectorAll(".stamp-mark"), (node) => node.textContent),
  }));
  // Both hydrations mount their row children into the one shared inventory,
  // crew's before pins' — the hydrate transactions run in declaration order.
  expect(hydrated.count).toBe(6);
  expect(hydrated.tags).toEqual(["Tag A", "Pin A", "Pin B", "static badge"]);
  expect(hydrated.marks).toEqual(["Alpha", "crew stamp"]);
  for (const event of [
    "event:hydrate:crew", "region:crew:hydrate", "storage:crew:write",
    "event:hydrate:pins", "region:pins:hydrate", "storage:pins:write",
  ]) {
    expect(hydrated.trace).toContain(event);
  }
  expect(hydrated.trace.indexOf("event:hydrate:crew"))
    .toBeLessThan(hydrated.trace.indexOf("event:hydrate:pins"));
  // A write in one region rewrites its own key alone.
  await page.locator("#pins > li").first()
    .getByRole("button", { name: "Remove pin" }).click();
  const afterPin = await page.evaluate(() => ({
    crew: localStorage.getItem("leanrx-mix-lab.crew"),
    pins: localStorage.getItem("leanrx-mix-lab.pins"),
  }));
  expect(afterPin.crew).toBe("Alpha,true,Tag A");
  expect(afterPin.pins).toBe("Pin B");
  await page.getByRole("button", { name: "Add member" }).click();
  const afterMember = await page.evaluate(() => ({
    crew: localStorage.getItem("leanrx-mix-lab.crew"),
    pins: localStorage.getItem("leanrx-mix-lab.pins"),
  }));
  expect(afterMember.crew).toBe("Alpha,true,Tag A;Member 0,false,Tag 0");
  expect(afterMember.pins).toBe("Pin B");
});

test("one chained event drains both regions in one commit", async ({ page }) => {
  await mountMix(page);
  const add = page.getByRole("button", { name: "Add member" });
  await add.click();
  await add.click();
  await page.locator("#crew > li").first()
    .getByRole("checkbox", { name: "Toggle member" }).check();
  await expect(page.locator("#crew-line")).toHaveText("1 done of 2");
  const before = await page.evaluate(() => {
    const tx = globalThis.mixDispose.instrumentation();
    globalThis.mixTraceLength = tx[7].length;
    return { commits: tx[1], length: tx[7].length };
  });
  // ADR-0078: `append pins (…) then remove crew (…) then set added (…)`
  // raises both dirty flags inside one transaction; the commit sweep then
  // drains them in region declaration order, crew before pins, regardless of
  // the order the event touched them.
  await page.getByRole("button", { name: "Stow done" }).click();
  await expect(page.locator("#crew > li .crew-label")).toHaveText(["Member 1"]);
  await expect(page.locator("#pins .pin-note")).toHaveText(["Stowed 2"]);
  await expect(page.locator("#crew-line")).toHaveText("0 done of 1");
  await expect(page.locator("#pins-line")).toHaveText("1 pinned");
  const after = await page.evaluate(() => {
    const tx = globalThis.mixDispose.instrumentation();
    return {
      commits: tx[1],
      slice: tx[7].slice(globalThis.mixTraceLength),
      children: globalThis.mixDispose.children.length,
      crew: localStorage.getItem("leanrx-mix-lab.crew"),
      pins: localStorage.getItem("leanrx-mix-lab.pins"),
    };
  });
  expect(after.commits).toBe(before.commits + 1);
  expect(after.slice.filter((event) => event === "transaction:commit")).toHaveLength(1);
  // Event order: pins append before the crew removal.
  expect(after.slice.indexOf("region:pins:append"))
    .toBeLessThan(after.slice.indexOf("region:crew:removeIf"));
  // Sweep order: crew reconcile and write-back before pins'.
  expect(after.slice.indexOf("region:crew:update"))
    .toBeLessThan(after.slice.indexOf("region:pins:update"));
  expect(after.slice.indexOf("storage:crew:write"))
    .toBeLessThan(after.slice.indexOf("storage:pins:write"));
  // One removal, one mount: the static seed, the surviving member's run of
  // three, and the pin.
  expect(after.children).toBe(5);
  expect(after.crew).toBe("Member 1,false,Tag 1");
  expect(after.pins).toBe("Stowed 2");
});

test("a filter flip in one region never touches the other", async ({ page }) => {
  await mountMix(page);
  await page.getByRole("button", { name: "Add member" }).click();
  await page.getByRole("button", { name: "Add pin" }).click();
  await page.locator("#pins .badge button").first().click();
  await expect(page.locator("#pins .badge-text")).toHaveText(["Hits: 1"]);
  const before = await page.evaluate(() => ({
    pinMetrics: globalThis.mixDispose.regionInstrumentation()[1],
    children: (globalThis.mixEntries = globalThis.mixDispose.children.slice()).length,
    pins: localStorage.getItem("leanrx-mix-lab.pins"),
  }));
  // ADR-0078: the filter sweep is the one filtered region's own — its scan
  // walks crew's row table through crew's own container slot, and the
  // unfiltered neighbour has no scan, no touched flag, and no write-back.
  await page.getByRole("button", { name: "Show done" }).click();
  await expect(page.locator("#crew > li").first()).toBeHidden();
  await expect(page.locator("#pins > li").first()).toBeVisible();
  await expect(page.locator("#pins .badge-text")).toHaveText(["Hits: 1"]);
  await expect(page.locator("#pins-line")).toHaveText("1 pinned");
  const after = await page.evaluate(() => ({
    pinMetrics: globalThis.mixDispose.regionInstrumentation()[1],
    identical: globalThis.mixDispose.children.every(
      (child, index) => child === globalThis.mixEntries[index],
    ),
    children: globalThis.mixDispose.children.length,
    pins: localStorage.getItem("leanrx-mix-lab.pins"),
  }));
  expect(after.pinMetrics).toEqual(before.pinMetrics);
  expect(after.identical).toBe(true);
  expect(after.children).toBe(before.children);
  expect(after.pins).toBe(before.pins);
});

test("root disposal disposes row badges while the inventory keeps reachability", async ({ page }) => {
  await mountMix(page);
  const add = page.getByRole("button", { name: "Add member" });
  await add.click();
  await add.click();
  await page.locator("#crew .badge button").first().click();
  const before = await page.evaluate(() => {
    globalThis.rowBadgeButtons = Array.from(
      document.querySelectorAll("#crew .badge button, #crew .stamp button"),
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
  expect(after.count).toBe(7);
  expect(after.attachedCount).toBe(0);
  expect(after.snapshot).toEqual(before);
});
