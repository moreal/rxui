import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_BROWSER_DIST;
if (!directory) throw new Error("LEANRX_BROWSER_DIST is required");

const files = new Set(["Counter.mjs", "leanrx_dom.mjs"]);
let server;
let origin;

test.beforeAll(async () => {
  server = createServer(async (request, response) => {
    try {
      const requested = new URL(request.url, "http://localhost").pathname.slice(1);
      if (requested === "") {
        response.setHeader("content-type", "text/html; charset=utf-8");
        response.end(`<!doctype html>
          <html lang="en"><head><title>LeanRx Counter test</title></head><body>
          <div id="one"></div><div id="two"></div>
          </body></html>`);
      } else if (files.has(requested)) {
        response.setHeader("content-type", "text/javascript; charset=utf-8");
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
  const address = server.address();
  origin = `http://127.0.0.1:${address.port}`;
});

test.afterAll(async () => {
  await new Promise((resolve, reject) =>
    server.close((error) => (error ? reject(error) : resolve())),
  );
});

async function openCounter(page, targets = ["one"]) {
  await page.goto(origin);
  await page.evaluate(async (mountTargets) => {
    const { mount } = await import("/Counter.mjs");
    globalThis.leanrxDisposers = mountTargets.map((id) =>
      mount(document.getElementById(id)),
    );
  }, targets);
}

test("mounts initial DOM, uses safe text, and passes accessibility scan", async ({ page }) => {
  await openCounter(page);
  await expect(page.locator("#one .counter p")).toHaveText([
    "Count: 1",
    "Doubled: 2",
    "Parity: odd",
    "Stable",
    '<img src=x onerror="globalThis.leanrxXss=true">',
  ]);
  await expect(page.locator("#one button").first()).toHaveAttribute("type", "button");

  const hostile = page.locator("#one .counter p").nth(4);
  await expect(hostile).toHaveText('<img src=x onerror="globalThis.leanrxXss=true">');
  await expect(hostile.locator("img")).toHaveCount(0);
  expect(await page.evaluate(() => globalThis.leanrxXss)).toBeUndefined();

  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("increment updates count, doubled, and parity with keyboard activation", async ({ page }) => {
  await openCounter(page);
  await page.keyboard.press("Tab");
  await expect(page.locator("#one button").first()).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page.locator("#one .counter p")).toHaveText([
    "Count: 2",
    "Doubled: 4",
    "Parity: even",
    "Stable",
    '<img src=x onerror="globalThis.leanrxXss=true">',
  ]);
});

test("add two suppresses the unchanged parity text write", async ({ page }) => {
  await openCounter(page);
  await page.evaluate(() => {
    const parity = document.querySelector("#one .counter p:nth-of-type(3)").firstChild;
    globalThis.parityMutations = 0;
    const observer = new MutationObserver((records) => {
      globalThis.parityMutations += records.length;
    });
    observer.observe(parity, { characterData: true });
    globalThis.parityObserver = observer;
  });
  await page.locator("#one button").nth(1).click();
  await expect(page.locator("#one .counter p")).toHaveText([
    "Count: 3",
    "Doubled: 6",
    "Parity: odd",
    "Stable",
    '<img src=x onerror="globalThis.leanrxXss=true">',
  ]);
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => resolve())));
  expect(await page.evaluate(() => globalThis.parityMutations)).toBe(0);
  const instrumentation = await page.evaluate(() => globalThis.leanrxDisposers[0].instrumentation());
  expect(instrumentation.slice(0, 7)).toEqual([0, 1, 2, 2, 1, 3, 2]);
  expect(instrumentation.slice(8, 10)).toEqual([0, 0]);
  expect(instrumentation[7]).toEqual([
    "transaction:begin",
    "event:addTwo",
    "source:count:write",
    "source:count:write",
    "source:count:changed",
    "derived:doubled:evaluated",
    "derived:doubled:changed",
    "derived:parity:evaluated",
    "sink:countText:evaluated",
    "dom:countText:write",
    "sink:doubledText:evaluated",
    "dom:doubledText:write",
    "sink:stableText:evaluated",
    "transaction:commit",
  ]);
});

test("nested dispatch batches into the outer transaction", async ({ page }) => {
  await openCounter(page);
  await page.evaluate(() => {
    const snapshot = globalThis.leanrxDisposers[0].instrumentation();
    snapshot[0] = 99;
    snapshot[7].push("consumer:mutation");
    snapshot[8] = 99;
    snapshot[9] = 99;
  });
  await page.locator("#one button").nth(2).click();
  await expect(page.locator("#one .counter p").first()).toHaveText("Count: 3");
  const instrumentation = await page.evaluate(() => globalThis.leanrxDisposers[0].instrumentation());
  expect(instrumentation.slice(0, 7)).toEqual([0, 1, 2, 2, 1, 3, 2]);
  expect(instrumentation.slice(8, 10)).toEqual([0, 0]);
  expect(instrumentation[7].filter((event) => event === "transaction:commit")).toHaveLength(1);
  expect(instrumentation[7].slice(0, 7)).toEqual([
    "transaction:begin",
    "event:nestedAddTwo",
    "event:increment",
    "source:count:write",
    "event:increment",
    "source:count:write",
    "source:count:changed",
  ]);
});

test("write then revert leaves the changed frontier empty", async ({ page }) => {
  await openCounter(page);
  await page.locator("#one button").nth(3).click();
  await expect(page.locator("#one .counter p").first()).toHaveText("Count: 1");
  const instrumentation = await page.evaluate(() => globalThis.leanrxDisposers[0].instrumentation());
  expect(instrumentation.slice(0, 7)).toEqual([0, 1, 2, 0, 0, 0, 0]);
  expect(instrumentation[7]).toEqual([
    "transaction:begin",
    "event:roundTrip",
    "source:count:write",
    "source:count:write",
    "transaction:commit",
  ]);
});

test("mount instances are isolated and disposal is idempotent", async ({ page }) => {
  await openCounter(page, ["one", "two"]);
  await page.locator("#one button").first().click();
  await expect(page.locator("#one .counter p").first()).toHaveText("Count: 2");
  await expect(page.locator("#two .counter p").first()).toHaveText("Count: 1");

  const detachedText = await page.evaluate(() => {
    const root = document.querySelector("#one .counter");
    const button = root.querySelector("button");
    const countText = root.querySelector("p").firstChild;
    globalThis.leanrxDisposers[0]();
    globalThis.leanrxDisposers[0]();
    button.click();
    return countText.data;
  });
  expect(detachedText).toBe("Count: 2");
  await expect(page.locator("#one .counter")).toHaveCount(0);
  await expect(page.locator("#two .counter")).toHaveCount(1);
});

test("nextText walks a template's text slots in document order without stopping at its root", async ({ page }) => {
  await page.goto(origin);
  const result = await page.evaluate(async () => {
    const { nextText } = await import("/leanrx_dom.mjs");
    const row = document.createElement("tr");
    const idCell = document.createElement("td");
    idCell.append(document.createTextNode("id"));
    const labelCell = document.createElement("td");
    const link = document.createElement("a");
    link.append(document.createComment("note"), document.createTextNode("label"));
    labelCell.append(link, document.createTextNode("tail"));
    const iconCell = document.createElement("td");
    iconCell.append(document.createElement("span"));
    row.append(idCell, labelCell, iconCell);
    const first = nextText(row);
    const second = nextText(first);
    const third = nextText(second);
    const detachedEnd = nextText(third);
    const emptyRow = document.createElement("tr");
    emptyRow.append(document.createElement("td"));
    const detachedEmpty = nextText(emptyRow);
    const host = document.getElementById("two");
    host.append(row, document.createTextNode("after"));
    const escaped = nextText(third);
    const escapedFromEmpty = nextText(iconCell);
    return {
      texts: [first.data, second.data, third.data],
      identity: first === idCell.firstChild && second === link.lastChild && third === labelCell.lastChild,
      detachedEnd,
      detachedEmpty,
      escaped: escaped.data,
      escapedFromEmpty: escapedFromEmpty.data,
      fromText: nextText(first) === second,
    };
  });
  expect(result).toEqual({
    texts: ["id", "label", "tail"],
    identity: true,
    detachedEnd: null,
    detachedEmpty: null,
    escaped: "after",
    escapedFromEmpty: "after",
    fromText: true,
  });
});

test("listenDelegatedCells resolves a keyed row's action from the clicked cell", async ({ page }) => {
  await page.goto(origin);
  const result = await page.evaluate(async () => {
    const { listenDelegatedCells, setKey } = await import("/leanrx_dom.mjs");
    const host = document.getElementById("two");
    const table = document.createElement("table");
    const body = document.createElement("tbody");
    table.append(body);
    host.append(table);
    const makeRow = (key) => {
      const row = document.createElement("tr");
      const idCell = document.createElement("td");
      idCell.append(document.createTextNode(key));
      const labelCell = document.createElement("td");
      const link = document.createElement("a");
      link.append(document.createTextNode("label"));
      labelCell.append(link);
      const removeCell = document.createElement("td");
      const removeLink = document.createElement("a");
      const icon = document.createElement("span");
      removeLink.append(icon);
      removeCell.append(removeLink);
      const filler = document.createElement("td");
      row.append(idCell, labelCell, removeCell, filler);
      setKey(row, key);
      body.append(row);
      return { row, idCell, labelCell, link, removeLink, icon, filler };
    };
    const first = makeRow("7");
    const second = makeRow("8");
    const unkeyed = document.createElement("tr");
    const unkeyedCell = document.createElement("td");
    const unkeyedLink = document.createElement("a");
    unkeyedCell.append(unkeyedLink);
    unkeyed.append(unkeyedCell);
    body.append(unkeyed);
    const state = ["state"];
    const context = ["context"];
    const calls = [];
    const off = listenDelegatedCells(body, "click", state, context,
      (...args) => calls.push(args), ["", "select", "remove", ""]);
    const click = (node) => node.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    click(first.link);
    click(second.icon);
    click(second.removeLink);
    click(first.idCell);
    click(first.filler);
    click(second.labelCell);
    click(second.row);
    click(unkeyedLink);
    click(body);
    const dispatched = calls.length;
    off();
    click(first.link);
    table.remove();
    return {
      calls: calls.map(([givenState, givenContext, action, key, value, checked, eventKey]) =>
        [givenState === state && givenContext === context, action, key, value, checked, eventKey]),
      afterDispose: calls.length - dispatched,
    };
  });
  expect(result).toEqual({
    calls: [
      [true, "select", "7", "", false, ""],
      [true, "remove", "8", "", false, ""],
      [true, "remove", "8", "", false, ""],
    ],
    afterDispose: 0,
  });
});

test("readHash and writeHash read and assign the location hash (ADR-0063)", async ({ page }) => {
  await page.goto(origin);
  const result = await page.evaluate(async () => {
    const { readHash, writeHash } = await import("/leanrx_dom.mjs");
    const initial = readHash();
    writeHash("#/route-check");
    const written = readHash() === "#/route-check" && location.hash === "#/route-check";
    writeHash("#/");
    const rewritten = readHash();
    return { initial, written, rewritten };
  });
  expect(result).toEqual({ initial: "", written: true, rewritten: "#/" });
});

test("listenHash dispatches per hashchange with no equal-value echo (ADR-0063)", async ({ page }) => {
  await page.goto(origin);
  const result = await page.evaluate(async () => {
    const { listenHash, writeHash } = await import("/leanrx_dom.mjs");
    const state = ["state"];
    const context = ["context"];
    const calls = [];
    const off = listenHash(state, context, (...args) => calls.push(args));
    const settle = () => new Promise((resolve) => setTimeout(resolve, 50));
    writeHash("#/active");
    await settle();
    const afterFirst = calls.length;
    // A WHATWG equal-value assignment fires no hashchange, so the generated
    // flip-only write cannot echo through its own listener.
    writeHash("#/active");
    await settle();
    const afterEqual = calls.length;
    off();
    writeHash("#/completed");
    await settle();
    return {
      identity: calls.every(([givenState, givenContext]) =>
        givenState === state && givenContext === context),
      hashes: calls.map(([, , hash]) => hash),
      afterFirst,
      afterEqual,
      afterDispose: calls.length,
    };
  });
  expect(result).toEqual({
    identity: true,
    hashes: ["#/active"],
    afterFirst: 1,
    afterEqual: 1,
    afterDispose: 1,
  });
});

test("storageGet and storageSet move one string through localStorage (ADR-0063)", async ({ page }) => {
  await page.goto(origin);
  const result = await page.evaluate(async () => {
    const { storageGet, storageSet } = await import("/leanrx_dom.mjs");
    const missing = storageGet("leanrx-spec-missing");
    storageSet("leanrx-spec-key", "a,b;c%25 value");
    const roundTrip = storageGet("leanrx-spec-key");
    const agreement = localStorage.getItem("leanrx-spec-key") === roundTrip;
    localStorage.removeItem("leanrx-spec-key");
    return { missing, roundTrip, agreement };
  });
  expect(result).toEqual({
    missing: null,
    roundTrip: "a,b;c%25 value",
    agreement: true,
  });
});

test("focus moves keyboard focus to an attached input and only then (ADR-0048)", async ({ page }) => {
  await page.goto(origin);
  const result = await page.evaluate(async () => {
    const { focus } = await import("/leanrx_dom.mjs");
    const host = document.getElementById("two");
    const input = document.createElement("input");
    input.value = "draft";
    host.append(input);
    const mountedInert = document.activeElement !== input;
    focus(input);
    const focused = document.activeElement === input;
    const blocker = document.createElement("input");
    host.append(blocker);
    focus(blocker);
    const moved = document.activeElement === blocker;
    input.remove();
    blocker.remove();
    return { mountedInert, focused, moved };
  });
  expect(result).toEqual({ mountedInert: true, focused: true, moved: true });
});
