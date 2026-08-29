import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_NOTES_DIST;
if (!directory) throw new Error("LEANRX_NOTES_DIST is required");

const files = new Set([
  "Notes.mjs",
  "Notes.expected.json",
  "leanrx_dom.mjs",
  "leanrx_form_events.mjs",
  "leanrx_effects.mjs",
]);
let server;
let origin;

test.beforeAll(async () => {
  server = createServer(async (request, response) => {
    try {
      const requested = new URL(request.url, "http://localhost").pathname.slice(1);
      if (requested === "") {
        response.setHeader("content-type", "text/html; charset=utf-8");
        response.end("<!doctype html><html lang=\"en\"><head><title>Notes</title></head><body><div id=\"app\"></div><div id=\"second\"></div><div id=\"third\"></div></body></html>");
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

test("restores, debounces, reports storage errors, and cancels owned work", async ({ page }) => {
  const pageErrors = [];
  page.on("pageerror", (error) => pageErrors.push(error.message));
  await page.goto(origin);
  const expected = await page.evaluate(async () => (await fetch("/Notes.expected.json")).json());
  await page.evaluate(async ({ storageKey }) => {
    localStorage.setItem(storageKey, "restored note");
    const { mount } = await import("/Notes.mjs");
    globalThis.notesDispose = mount(document.getElementById("app"));
  }, expected);

  const root = page.locator(".leanrx-notes");
  const input = root.getByRole("textbox", { name: "Note" });
  const status = root.getByRole("status");
  await expect(input).toHaveValue("restored note");
  await expect(status).toHaveText(expected.initialStatus);
  await expect(root.locator("img")).toHaveCount(0);
  expect(await page.evaluate(() => globalThis.notesXss)).toBeUndefined();
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);

  await input.fill("first draft");
  await page.waitForTimeout(Math.floor(expected.debounceMs / 2));
  await input.fill("final draft");
  await expect(status).toHaveText(expected.waitingStatus);
  expect(await page.evaluate(({ storageKey }) => localStorage.getItem(storageKey), expected))
    .toBe("restored note");
  await expect(status).toHaveText("Saved", { timeout: expected.debounceMs * 4 });
  expect(await page.evaluate(({ storageKey }) => localStorage.getItem(storageKey), expected))
    .toBe("final draft");
  expect(await page.evaluate(() => globalThis.notesDispose.effectInstrumentation())).toEqual([4, 1]);
  expect(await page.evaluate(() => globalThis.notesDispose.instrumentation().slice(8, 10)))
    .toEqual([4, 1]);

  await page.evaluate(() => {
    globalThis.notesOriginalSetItem = Storage.prototype.setItem;
    Storage.prototype.setItem = function setItem() { throw new Error("quota exceeded"); };
  });
  await input.fill("cannot save");
  await expect(status).toHaveText(expected.saveFailureStatus, {
    timeout: expected.debounceMs * 4,
  });
  await page.evaluate(() => { Storage.prototype.setItem = globalThis.notesOriginalSetItem; });
  await input.fill("recovered save");
  await expect(status).toHaveText(expected.waitingStatus);
  await expect(status).toHaveText("Saved", { timeout: expected.debounceMs * 4 });

  await page.evaluate(async () => {
    let resolveRestore;
    globalThis.resolveNotesRestore = (value) => resolveRestore(value);
    const storage = {
      getItem: () => new Promise((resolve) => { resolveRestore = resolve; }),
      setItem: (key, value) => localStorage.setItem(key, value),
    };
    const { mount } = await import("/Notes.mjs");
    globalThis.secondNotesDispose = mount(document.getElementById("second"), { storage });
  });
  const second = page.locator("#second .leanrx-notes");
  const secondInput = second.getByRole("textbox", { name: "Note" });
  await expect(second.getByRole("status")).toHaveText(expected.initialStatus);
  await secondInput.fill("local wins");
  await page.evaluate(() => globalThis.resolveNotesRestore("stale restore"));
  await page.waitForTimeout(0);
  await expect(secondInput).toHaveValue("local wins");

  await secondInput.fill("dispose before debounce");
  const beforeDispose = await page.evaluate(({ storageKey }) => localStorage.getItem(storageKey), expected);
  await page.evaluate(() => globalThis.secondNotesDispose());
  await page.waitForTimeout(expected.debounceMs * 2);
  expect(await page.evaluate(({ storageKey }) => localStorage.getItem(storageKey), expected))
    .toBe(beforeDispose);
  expect(await page.evaluate(() => globalThis.secondNotesDispose.effectInstrumentation()[1]))
    .toBeGreaterThanOrEqual(2);

  await page.evaluate(async () => {
    const storage = {
      getItem: () => { throw new Error("restore broke"); },
      setItem: (key, value) => localStorage.setItem(key, value),
    };
    const { mount } = await import("/Notes.mjs");
    globalThis.thirdNotesDispose = mount(document.getElementById("third"), { storage });
  });
  const third = page.locator("#third .leanrx-notes");
  const thirdInput = third.getByRole("textbox", { name: "Note" });
  const thirdStatus = third.getByRole("status");
  await expect(thirdStatus).toHaveText(expected.restoreFailureStatus);
  await thirdInput.fill("saved despite restore failure");
  await page.waitForTimeout(expected.debounceMs * 2);
  await expect(thirdStatus).toHaveText(expected.restoreFailureStatus);
  expect(await page.evaluate(({ storageKey }) => localStorage.getItem(storageKey), expected))
    .toBe("saved despite restore failure");
  await page.evaluate(() => globalThis.thirdNotesDispose());
  expect(pageErrors).toEqual([]);
});

test("the restored textarea declares the program's ownership (ADR-0105)", async ({ page }) => {
  await page.goto(origin);
  const expected = await page.evaluate(async () => (await fetch("/Notes.expected.json")).json());
  await page.evaluate(async ({ storageKey }) => {
    localStorage.setItem(storageKey, "restored note");
    const { mount } = await import("/Notes.mjs");
    globalThis.notesOwnedDispose = mount(document.getElementById("app"));
  }, expected);
  const owned = () => page.evaluate(() =>
    document.querySelectorAll('[autocomplete="off"]').length);
  // The restore effect writes state[0] back into the textarea, which is the
  // claim being declared -- and a <textarea> is the one shape the checked
  // pipeline cannot emit, so this is the rule's only reach to one.
  expect(await owned()).toBe(1);
  const input = page.locator(".leanrx-notes").getByRole("textbox", { name: "Note" });
  await expect(input).toHaveValue("restored note");
  await expect(input).toHaveAttribute("autocomplete", "off");
  await page.evaluate(() => globalThis.notesOwnedDispose());
  expect(await owned()).toBe(0);
});
