import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_JS_FRAMEWORK_BENCHMARK_DIST;
test.skip(!directory, "LEANRX_JS_FRAMEWORK_BENCHMARK_DIST is required");

const files = new Set(["index.html", "main.mjs"]);
let server;
let origin;

test.beforeAll(async () => {
  server = createServer(async (request, response) => {
    try {
      const requested = new URL(request.url, "http://localhost").pathname.slice(1);
      if (requested === "css/currentStyle.css") {
        response.setHeader("content-type", "text/css; charset=utf-8");
        response.end("");
      } else {
        const file = requested === "" ? "index.html" : requested;
        if (!files.has(file)) {
          response.statusCode = 404;
          response.end("not found");
          return;
        }
        response.setHeader(
          "content-type",
          file.endsWith(".html") ? "text/html; charset=utf-8" : "text/javascript",
        );
        response.end(await readFile(path.join(directory, file)));
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

test("@framework-benchmark implements the upstream keyed table contract", async ({ page }) => {
  test.setTimeout(180000);
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error)));
  await page.goto(origin);

  const rows = page.locator("tbody > tr");
  await expect(page.locator("#run")).toHaveText("Create 1,000 rows");
  await expect(page.locator("#runlots")).toHaveText("Create 10,000 rows");
  await expect(page.locator("#add")).toHaveText("Append 1,000 rows");
  await expect(page.locator("#update")).toHaveText("Update every 10th row");
  await expect(page.locator("#clear")).toHaveText("Clear");
  await expect(page.locator("#swaprows")).toHaveText("Swap Rows");
  await expect(rows).toHaveCount(0);

  await page.locator("#add").click();
  await expect(rows).toHaveCount(1000);
  await expect(rows.first().locator("td").first()).toHaveText("1");
  await expect(rows.last().locator("td").first()).toHaveText("1000");
  expect(await rows.last().evaluate((row) =>
    [...row.querySelectorAll("*")].map((node) => node.tagName.toLowerCase())))
    .toEqual(["td", "td", "a", "td", "a", "span", "td"]);
  await expect(rows.last().locator("td").nth(0)).toHaveClass("col-md-1");
  await expect(rows.last().locator("td").nth(1)).toHaveClass("col-md-4");
  await expect(rows.last().locator("td").nth(2)).toHaveClass("col-md-1");
  await expect(rows.last().locator("td").nth(3)).toHaveClass("col-md-6");
  await expect(rows.last().locator("span.glyphicon.glyphicon-remove"))
    .toHaveAttribute("aria-hidden", "true");

  await rows.nth(1).evaluate((row) => { globalThis.leanrxSecondRow = row; });
  await rows.nth(998).evaluate((row) => { globalThis.leanrxNineNinetyNinthRow = row; });
  await page.locator("#swaprows").click();
  await expect(rows.nth(1).locator("td").first()).toHaveText("999");
  await expect(rows.nth(998).locator("td").first()).toHaveText("2");
  expect(await rows.nth(1).evaluate((row) => row === globalThis.leanrxNineNinetyNinthRow))
    .toBe(true);
  expect(await rows.nth(998).evaluate((row) => row === globalThis.leanrxSecondRow)).toBe(true);

  await page.locator("#run").click();
  await expect(rows).toHaveCount(1000);
  await expect(rows.first().locator("td").first()).toHaveText("1001");
  await expect(rows.last().locator("td").first()).toHaveText("2000");
  expect(await page.evaluate(() => globalThis.leanrxSecondRow.isConnected)).toBe(false);

  const changedBefore = await rows.first().locator("td").nth(1).textContent();
  const unchangedBefore = await rows.nth(1).locator("td").nth(1).textContent();
  await page.locator("#update").click();
  await expect(rows.first().locator("td").nth(1)).toHaveText(`${changedBefore} !!!`);
  await expect(rows.nth(1).locator("td").nth(1)).toHaveText(unchangedBefore);
  expect(await rows.evaluateAll((allRows) => allRows.filter((row) =>
    row.children[1].textContent.endsWith(" !!!")).length)).toBe(100);

  await rows.nth(1).locator("td").nth(1).locator("a").click();
  await expect(rows.nth(1)).toHaveClass("danger");
  await expect(page.locator("tbody > tr.danger")).toHaveCount(1);
  await rows.nth(2).evaluate((row) => { globalThis.leanrxThirdRow = row; });
  await rows.nth(1).locator("td").nth(2).locator("span")
    .evaluate((element) => element.click());
  await expect(rows).toHaveCount(999);
  await expect(rows.nth(1).locator("td").first()).toHaveText("1003");
  expect(await rows.nth(1).evaluate((row) => row === globalThis.leanrxThirdRow)).toBe(true);
  await expect(page.locator("tbody > tr.danger")).toHaveCount(0);

  await page.locator("#runlots").click();
  await expect(rows).toHaveCount(10000);
  await expect(rows.first().locator("td").first()).toHaveText("2001");
  await expect(rows.last().locator("td").first()).toHaveText("12000");
  await page.locator("#clear").click();
  await expect(rows).toHaveCount(0);

  const disposal = await page.evaluate(() => {
    const detachedRun = document.getElementById("run");
    const before = globalThis.leanrxBenchmarkDispose.instrumentation();
    globalThis.leanrxBenchmarkDispose();
    globalThis.leanrxBenchmarkDispose();
    detachedRun.click();
    return { before, after: globalThis.leanrxBenchmarkDispose.instrumentation() };
  });
  expect(disposal.after).toEqual(disposal.before);
  await expect(page.locator("#main")).toHaveCount(0);
  expect(errors).toEqual([]);
});

test("@framework-benchmark preserves model state across composed keyed operations", async ({ page }) => {
  test.setTimeout(180000);
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error)));
  await page.goto(origin);

  const rows = page.locator("tbody > tr");
  await page.locator("#run").click();
  await expect(rows).toHaveCount(1000);

  const selectedRow = rows.nth(10);
  const stableRow = rows.nth(11);
  await selectedRow.evaluate((row) => { globalThis.leanrxSelectedRow = row; });
  await stableRow.evaluate((row) => { globalThis.leanrxStableRow = row; });
  await selectedRow.locator("td").nth(1).locator("a").click();
  await expect(selectedRow).toHaveClass("danger");

  const selectedLabel = await selectedRow.locator("td").nth(1).textContent();
  await page.locator("#update").click();
  await expect(selectedRow.locator("td").nth(1)).toHaveText(`${selectedLabel} !!!`);
  await expect(selectedRow).toHaveClass("danger");
  expect(await selectedRow.evaluate((row) => row === globalThis.leanrxSelectedRow)).toBe(true);
  expect(await stableRow.evaluate((row) => row === globalThis.leanrxStableRow)).toBe(true);

  await page.locator("#update").click();
  await expect(selectedRow.locator("td").nth(1)).toHaveText(`${selectedLabel} !!! !!!`);
  await expect(selectedRow).toHaveClass("danger");

  await page.locator("#add").click();
  await expect(rows).toHaveCount(2000);
  await expect(selectedRow).toHaveClass("danger");
  await expect(rows.nth(1000).locator("td").first()).toHaveText("1001");
  await expect(rows.last().locator("td").first()).toHaveText("2000");
  expect(await selectedRow.evaluate((row) => row === globalThis.leanrxSelectedRow)).toBe(true);

  await rows.nth(1).locator("td").nth(1).locator("a").click();
  await rows.nth(1).evaluate((row) => { globalThis.leanrxSwappedSelection = row; });
  await page.locator("#swaprows").click();
  await expect(rows.nth(998).locator("td").first()).toHaveText("2");
  await expect(rows.nth(998)).toHaveClass("danger");
  expect(await rows.nth(998).evaluate((row) => row === globalThis.leanrxSwappedSelection))
    .toBe(true);

  await rows.first().locator("td").nth(2).locator("span")
    .evaluate((element) => element.click());
  await expect(rows).toHaveCount(1999);
  await expect(page.locator("tbody > tr.danger")).toHaveCount(1);
  await expect(page.locator("tbody > tr.danger").locator("td").first()).toHaveText("2");
  expect(await page.evaluate(() => globalThis.leanrxSwappedSelection.isConnected)).toBe(true);
  expect(errors).toEqual([]);
});

test("@framework-benchmark ignores operations whose model preconditions do not hold", async ({ page }) => {
  test.setTimeout(180000);
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error)));
  await page.goto(origin);

  const rows = page.locator("tbody > tr");
  await page.locator("#run").click();
  await rows.nth(4).locator("td").nth(1).locator("a").click();
  await expect(rows.nth(4)).toHaveClass("danger");

  await rows.nth(5).evaluate((row) => { row.$lrxKey = "1001"; });
  const unknownSelect = rows.nth(5).locator("td").nth(1).locator("a");
  await unknownSelect.click();
  await expect(rows.nth(4)).toHaveClass("danger");
  await expect(page.locator("tbody > tr.danger")).toHaveCount(1);

  const unknownRemove = rows.nth(5).locator("td").nth(2).locator("a");
  await unknownRemove.evaluate((element) => element.click());
  await expect(rows).toHaveCount(1000);
  await expect(rows.nth(4)).toHaveClass("danger");

  await page.locator("#clear").click();
  await page.locator("#swaprows").click();
  await expect(rows).toHaveCount(0);
  expect(errors).toEqual([]);
});
