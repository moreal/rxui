import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_TEMPERATURE_DIST;
if (!directory) throw new Error("LEANRX_TEMPERATURE_DIST is required");

const files = new Set([
  "TemperatureConverter.mjs",
  "Temperature.expected.json",
  "leanrx_dom.mjs",
  "leanrx_host.mjs",
]);
let server;
let origin;

test.beforeAll(async () => {
  server = createServer(async (request, response) => {
    try {
      const requested = new URL(request.url, "http://localhost").pathname.slice(1);
      if (requested === "") {
        response.setHeader("content-type", "text/html; charset=utf-8");
        response.end("<!doctype html><html lang=\"en\"><head><title>Temperature Converter</title></head><body><div id=\"app\"></div></body></html>");
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

async function dispatchValue(page, index, value, cursor = value.length) {
  return page.locator(".temperature-converter input").nth(index).evaluate(
    (input, payload) => {
      input.value = payload.value;
      input.focus();
      input.setSelectionRange(payload.cursor, payload.cursor);
      input.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText" }));
      return { value: input.value, cursor: input.selectionStart };
    },
    { value, cursor },
  );
}

test("preserves raw edits and converts only successfully parsed input", async ({ page }) => {
  await page.goto(origin);
  const expected = await page.evaluate(async () => (await fetch("/Temperature.expected.json")).json());
  await page.evaluate(async () => {
    const { mount } = await import("/TemperatureConverter.mjs");
    globalThis.temperatureDispose = mount(document.getElementById("app"));
  });
  const inputs = page.locator(".temperature-converter input");
  const error = page.locator(".temperature-converter p");
  await expect(inputs.nth(0)).toHaveValue("0");
  await expect(inputs.nth(1)).toHaveValue("32");

  const cursor = await dispatchValue(page, 0, "120", 1);
  expect(cursor).toEqual({ value: "120", cursor: 1 });
  await expect(inputs.nth(1)).toHaveValue("248");
  await expect(error).toHaveText("");

  const invalid = await dispatchValue(page, 0, '<img src=x onerror="globalThis.tempXss=true">', 4);
  expect(invalid.cursor).toBe(4);
  await expect(inputs.nth(0)).toHaveValue('<img src=x onerror="globalThis.tempXss=true">');
  await expect(inputs.nth(1)).toHaveValue("248");
  await expect(error).toHaveText("Enter an integer Celsius temperature.");
  await expect(page.locator(".temperature-converter img")).toHaveCount(0);
  expect(await page.evaluate(() => globalThis.tempXss)).toBeUndefined();

  for (const testCase of expected) {
    const index = testCase.scale === "celsius" ? 0 : 1;
    const other = index === 0 ? 1 : 0;
    await dispatchValue(page, index, testCase.raw);
    await expect(inputs.nth(other)).toHaveValue(testCase.converted);
    await expect(error).toHaveText("");
  }

  const instrumentation = await page.evaluate(() =>
    globalThis.temperatureDispose.instrumentation(),
  );
  expect(instrumentation[1]).toBe(6);
  expect(instrumentation[2]).toBe(6);
  expect(instrumentation[3]).toBe(6);
  expect(instrumentation[7].filter((entry) => entry === "transaction:commit")).toHaveLength(6);
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});
