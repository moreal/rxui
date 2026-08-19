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
        response.end("<!doctype html><html lang=\"en\"><head><title>Temperature Converter</title></head><body><div id=\"app\"></div><div id=\"left\"></div><div id=\"right\"></div></body></html>");
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
  await expect(inputs.nth(0)).toHaveAttribute("aria-invalid", "false");
  await expect(inputs.nth(1)).toHaveAttribute("aria-invalid", "false");
  const describedBy = await inputs.nth(0).getAttribute("aria-describedby");
  expect(describedBy).toBeTruthy();
  await expect(inputs.nth(1)).toHaveAttribute("aria-describedby", describedBy);
  await expect(error).toHaveAttribute("id", describedBy);

  const cursor = await dispatchValue(page, 0, "00120", 2);
  expect(cursor).toEqual({ value: "00120", cursor: 2 });
  await expect(inputs.nth(1)).toHaveValue("248");
  await expect(error).toHaveText("");

  const invalid = await dispatchValue(page, 0, '<img src=x onerror="globalThis.tempXss=true">', 4);
  expect(invalid.cursor).toBe(4);
  await expect(inputs.nth(0)).toHaveValue('<img src=x onerror="globalThis.tempXss=true">');
  await expect(inputs.nth(1)).toHaveValue("248");
  await expect(error).toHaveText("Enter an integer Celsius temperature.");
  await expect(inputs.nth(0)).toHaveAttribute("aria-invalid", "true");
  await expect(inputs.nth(1)).toHaveAttribute("aria-invalid", "false");
  await expect(page.locator(".temperature-converter img")).toHaveCount(0);
  expect(await page.evaluate(() => globalThis.tempXss)).toBeUndefined();

  for (const separated of ["1_000", "-0_1"]) {
    await dispatchValue(page, 0, separated);
    await expect(inputs.nth(0)).toHaveValue(separated);
    await expect(inputs.nth(1)).toHaveValue("248");
    await expect(error).toHaveText("Enter an integer Celsius temperature.");
  }

  for (const testCase of expected) {
    const index = testCase.scale === "celsius" ? 0 : 1;
    const other = index === 0 ? 1 : 0;
    await dispatchValue(page, index, testCase.raw);
    await expect(inputs.nth(other)).toHaveValue(testCase.converted);
    await expect(error).toHaveText("");
    await expect(inputs.nth(0)).toHaveAttribute("aria-invalid", "false");
    await expect(inputs.nth(1)).toHaveAttribute("aria-invalid", "false");
  }

  const instrumentation = await page.evaluate(() =>
    globalThis.temperatureDispose.instrumentation(),
  );
  expect(instrumentation.slice(0, 7)).toEqual([0, 9, 24, 0, 0, 42, 10]);
  expect(instrumentation[7].filter((entry) => entry === "transaction:commit")).toHaveLength(9);
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("derives invalid observations from the complete checked state", async ({ page }) => {
  await page.goto(origin);
  await page.evaluate(async () => {
    const { mount } = await import("/TemperatureConverter.mjs");
    globalThis.temperatureOrderDisposers = [
      mount(document.getElementById("left")),
      mount(document.getElementById("right")),
    ];
  });
  const left = page.locator("#left .temperature-converter");
  const right = page.locator("#right .temperature-converter");
  const dispatch = async (input, value) => input.evaluate((node, next) => {
    node.value = next;
    node.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText" }));
  }, value);

  await dispatch(left.locator("input").nth(0), "bad-c");
  await dispatch(left.locator("input").nth(1), "bad-f");
  await dispatch(left.locator("input").nth(0), "bad-c");
  await dispatch(right.locator("input").nth(1), "bad-f");
  await dispatch(right.locator("input").nth(0), "bad-c");

  for (const root of [left, right]) {
    await expect(root.locator("input").nth(0)).toHaveValue("bad-c");
    await expect(root.locator("input").nth(1)).toHaveValue("bad-f");
    await expect(root.locator("input").nth(0)).toHaveAttribute("aria-invalid", "true");
    await expect(root.locator("input").nth(1)).toHaveAttribute("aria-invalid", "true");
    await expect(root.locator("p")).toHaveText("Enter an integer Celsius temperature.");
  }
  await page.evaluate(() => globalThis.temperatureOrderDisposers.forEach((dispose) => dispose()));
});
