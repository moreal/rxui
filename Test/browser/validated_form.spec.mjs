import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_VALIDATED_FORM_DIST;
if (!directory) throw new Error("LEANRX_VALIDATED_FORM_DIST is required");

const files = new Set([
  "ValidatedForm.mjs",
  "ValidatedForm.expected.json",
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
        response.end("<!doctype html><html lang=\"en\"><head><title>Validated Form</title></head><body><div id=\"one\"></div><div id=\"two\"></div></body></html>");
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

test("prevents invalid submit and exposes only a validated fake command", async ({ page }) => {
  await page.goto(origin);
  const expected = await page.evaluate(async () => (await fetch("/ValidatedForm.expected.json")).json());
  await page.evaluate(async () => {
    const { mount } = await import("/ValidatedForm.mjs");
    globalThis.formDisposers = [
      mount(document.getElementById("one")),
      mount(document.getElementById("two")),
    ];
  });
  const root = page.locator("#one .validated-form");
  const inputs = root.locator("input");
  const errors = root.locator("form > p");
  const submit = root.locator('button[type="submit"]');
  const status = root.locator('[role="status"]');

  await expect(errors).toHaveText([
    "name must not be empty",
    "value must be at least 18",
    "terms must be accepted",
  ]);
  await expect(submit).toBeDisabled();
  await expect(inputs.nth(0)).toHaveAttribute("aria-invalid", "true");
  await expect(inputs.nth(1)).toHaveAttribute("aria-invalid", "true");
  await expect(inputs.nth(2)).toHaveAttribute("aria-invalid", "true");
  const ids = await page.locator(".validated-form input[id]").evaluateAll((nodes) =>
    nodes.map((node) => node.id),
  );
  expect(new Set(ids).size).toBe(ids.length);
  for (const input of await inputs.all()) {
    if ((await input.getAttribute("type")) !== "checkbox") {
      const describedBy = await input.getAttribute("aria-describedby");
      await expect(root.locator(`#${describedBy}`)).toHaveCount(1);
    }
  }

  const prevented = await root.locator("form").evaluate((form) => {
    const event = new Event("submit", { bubbles: true, cancelable: true });
    form.dispatchEvent(event);
    return event.defaultPrevented;
  });
  expect(prevented).toBe(true);
  await expect(status).toHaveText("");
  expect(
    (await page.evaluate(() => globalThis.formDisposers[0].instrumentation()))[7],
  ).not.toContain("command:fakeSubmit");

  const hostile = '  <img src=x onerror="globalThis.formXss=true">  ';
  await inputs.nth(0).focus();
  await inputs.nth(0).fill(hostile);
  await page.keyboard.press("Tab");
  await inputs.nth(1).fill("1_0");
  await inputs.nth(1).press("Tab");
  await expect(errors.nth(1)).toHaveText(expected.invalid.lexicalAge);
  await expect(submit).toBeDisabled();
  await inputs.nth(1).focus();
  await inputs.nth(1).fill("42");
  await inputs.nth(1).press("Tab");
  await inputs.nth(2).check();
  await expect(errors).toHaveText(["", "", ""]);
  await expect(submit).toBeEnabled();
  await expect(inputs.nth(0)).toHaveAttribute("aria-invalid", "false");
  await expect(inputs.nth(1)).toHaveAttribute("aria-invalid", "false");
  await expect(inputs.nth(2)).toHaveAttribute("aria-invalid", "false");

  await inputs.nth(1).press("Enter");
  await expect(status).toHaveText(`Submitted ${expected.name} (${expected.age})`);
  await expect(root.locator("img")).toHaveCount(0);
  expect(await page.evaluate(() => globalThis.formXss)).toBeUndefined();
  const trace = (await page.evaluate(() => globalThis.formDisposers[0].instrumentation()))[7];
  expect(trace).toContain("event:keydown");
  expect(trace).toContain("event:focus");
  expect(trace).toContain("event:blur");
  expect(trace).toContain("event:submit");
  expect(trace).toContain("command:fakeSubmit");
  expect(trace).toContain("payload:key");
  expect(trace).not.toContain("Tab");

  await inputs.nth(1).focus();
  await inputs.nth(1).fill("121");
  await expect(errors.nth(1)).toHaveText(expected.invalid.upperAge);
  await expect(inputs.nth(1)).toHaveAttribute("aria-invalid", "true");
  await expect(submit).toBeDisabled();
  const rejectedAfterValid = await root.locator("form").evaluate((form) => {
    const event = new Event("submit", { bubbles: true, cancelable: true });
    form.dispatchEvent(event);
    return event.defaultPrevented;
  });
  expect(rejectedAfterValid).toBe(true);
  await inputs.nth(1).press("Tab");
  await expect(status).toHaveText(`Submitted ${expected.name} (${expected.age})`);
  const finalTrace = (await page.evaluate(() => globalThis.formDisposers[0].instrumentation()))[7];
  expect(finalTrace.filter((entry) => entry === "command:fakeSubmit")).toHaveLength(1);
  expect(finalTrace).toContain("event:change");
  expect(finalTrace).toContain("payload:text");
  expect(finalTrace.filter((entry) => entry === "sink:nameError:evaluated")).toHaveLength(4);
  expect(finalTrace.filter((entry) => entry === "sink:ageError:evaluated")).toHaveLength(6);
  expect(finalTrace.filter((entry) => entry === "sink:termsError:evaluated")).toHaveLength(4);
  expect(finalTrace.filter((entry) => entry === "sink:submitDisabled:evaluated")).toHaveLength(8);
  expect(finalTrace.filter((entry) => entry === "sink:submissionStatus:evaluated")).toHaveLength(1);
  const instrumentation = await page.evaluate(() => globalThis.formDisposers[0].instrumentation());
  expect(instrumentation.slice(0, 7)).toEqual([0, 8, 5, 0, 0, 23, 12]);

  await page.locator("#two .validated-form input").nth(0).fill("Second instance");
  await expect(inputs.nth(0)).toHaveValue(hostile);
  const disposedIsolation = await page.evaluate(() => {
    const detached = document.querySelector("#two .validated-form input");
    const before = globalThis.formDisposers[1].instrumentation().slice(0, 7);
    globalThis.formDisposers[1]();
    detached.value = "after disposal";
    detached.dispatchEvent(new InputEvent("input", { bubbles: true }));
    return { before, after: globalThis.formDisposers[1].instrumentation().slice(0, 7) };
  });
  expect(disposedIsolation.after).toEqual(disposedIsolation.before);
  await expect(page.locator("#two .validated-form")).toHaveCount(0);
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("the three controlled controls declare ownership and the buttons do not (ADR-0105)",
  async ({ page }) => {
  await page.goto(origin);
  await page.evaluate(async () => {
    const { mount } = await import("/ValidatedForm.mjs");
    globalThis.formOwnedDispose = mount(document.getElementById("one"));
  });
  const root = page.locator("#one .validated-form");
  // Two ADR-0038 text bindings and one `checked` binding: three controls the
  // program writes, three declarations. The submit button carries `disabled`
  // written from the same state and declares nothing, because `disabled` is
  // not state the browser restores.
  const owned = () => page.evaluate(() =>
    document.querySelectorAll('#one [autocomplete="off"]').length);
  expect(await owned()).toBe(3);
  await expect(root.locator('input[autocomplete="off"]')).toHaveCount(3);
  await expect(root.locator('button[autocomplete="off"]')).toHaveCount(0);
  await expect(root.locator('input[type="checkbox"][autocomplete="off"]')).toHaveCount(1);
  await page.evaluate(() => globalThis.formOwnedDispose());
  expect(await owned()).toBe(0);
});
