import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_ECHO_DIST;
if (!directory) throw new Error("LEANRX_ECHO_DIST is required");

const files = new Set([
  "EchoLab.mjs",
  "leanrx_dom.mjs",
  "leanrx_form_events.mjs",
]);
let server;
let origin;

test.beforeAll(async () => {
  server = createServer(async (request, response) => {
    try {
      const requested = new URL(request.url, "http://localhost").pathname.slice(1);
      if (requested === "") {
        response.setHeader("content-type", "text/html; charset=utf-8");
        response.end("<!doctype html><html lang=\"en\"><head><title>Echo Lab</title></head><body><div id=\"app\"></div></body></html>");
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

async function mountEcho(page) {
  await page.goto(origin);
  await page.evaluate(async () => {
    const { mount } = await import("/EchoLab.mjs");
    globalThis.echoDispose = mount(document.getElementById("app"));
  });
}

test("typed input payloads flow through generated typed events", async ({ page }) => {
  await mountEcho(page);
  await expect(page.locator("#draft-text")).toHaveText("Draft: ");
  await expect(page.locator("#summary-text")).toHaveText("Summary: (empty)");
  await page.locator("#draft").pressSequentially("hi");
  await expect(page.locator("#draft-text")).toHaveText("Draft: hi");
  await expect(page.locator("#key-text")).toHaveText("Key: i");
  await expect(page.locator("#summary-text")).toHaveText("Summary: hi");
  const trace = await page.evaluate(() => globalThis.echoDispose.instrumentation()[7]);
  expect(trace).toContain("event:setDraft");
  expect(trace).toContain("event:recordKey");
  expect(trace).toContain("source:draft:write");
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("change payloads commit on blur, not per keystroke", async ({ page }) => {
  await mountEcho(page);
  await page.locator("#note").pressSequentially("memo");
  await expect(page.locator("#note-text")).toHaveText("Note: ");
  await page.locator("#note").blur();
  await expect(page.locator("#note-text")).toHaveText("Note: memo");
});

test("payload-less click events coexist with typed events", async ({ page }) => {
  await mountEcho(page);
  await page.locator("#draft").pressSequentially("abc");
  await page.locator("#note").fill("memo");
  await page.locator("#note").blur();
  await expect(page.locator("#draft-text")).toHaveText("Draft: abc");
  await expect(page.locator("#note-text")).toHaveText("Note: memo");
  await page.getByRole("button", { name: "Clear" }).click();
  await expect(page.locator("#draft-text")).toHaveText("Draft: ");
  await expect(page.locator("#note-text")).toHaveText("Note: ");
  await expect(page.locator("#summary-text")).toHaveText("Summary: (empty)");
  await expect(page.locator("#key-text")).toHaveText("Key: c");
});

test("dispose removes typed listeners and the DOM", async ({ page }) => {
  await mountEcho(page);
  await page.locator("#draft").pressSequentially("x");
  await expect(page.locator("#draft-text")).toHaveText("Draft: x");
  await page.evaluate(() => {
    globalThis.echoInput = document.getElementById("draft");
    globalThis.echoDispose();
    globalThis.echoDispose();
  });
  await expect(page.locator(".echo-lab")).toHaveCount(0);
  await page.evaluate(() => {
    globalThis.echoInput.dispatchEvent(new Event("input", { bubbles: true }));
  });
  const trace = await page.evaluate(() => globalThis.echoDispose.instrumentation()[7]);
  expect(trace.filter((entry) => entry === "event:setDraft")).toHaveLength(1);
});
