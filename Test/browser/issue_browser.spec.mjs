import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_ISSUE_BROWSER_DIST;
if (!directory) throw new Error("LEANRX_ISSUE_BROWSER_DIST is required");

const files = new Set([
  "IssueBrowser.mjs",
  "IssueBrowser.expected.json",
  "leanrx_dom.mjs",
  "leanrx_host.mjs",
  "leanrx_region.mjs",
  "leanrx_effects.mjs",
  "leanrx_issue_ports.mjs",
]);
const requests = [];
const failureCounts = new Map();
let server;
let origin;

function issueBody(id, title, hasMore = false) {
  return JSON.stringify({ issues: [{ id, title }], hasMore });
}

test.beforeAll(async () => {
  server = createServer(async (request, response) => {
    try {
      const url = new URL(request.url, "http://localhost");
      const requested = url.pathname.slice(1);
      if (url.pathname === "/api/issues") {
        const query = url.searchParams.get("q") ?? "";
        const page = url.searchParams.get("page") ?? "";
        requests.push({ query, page });
        response.setHeader("content-type", "application/json; charset=utf-8");
        if (query === "slow" || query === "slow-dispose") {
          await new Promise((resolve) => setTimeout(resolve, 300));
          response.end(issueBody(query === "slow" ? 50 : 60, `Stale ${query}`));
        } else if (query === "bad") {
          response.end("{\"issues\":\"not-an-array\",\"hasMore\":false}");
        } else if (query === "failure") {
          const count = (failureCounts.get(query) ?? 0) + 1;
          failureCounts.set(query, count);
          if (count === 1) {
            response.statusCode = 503;
            response.end("{}");
          } else {
            response.end(issueBody(70, "Recovered issue"));
          }
        } else if (query === "duplicate") {
          response.end(JSON.stringify({
            issues: [{ id: 81, title: "Duplicate A" }, { id: 81, title: "Duplicate B" }],
            hasMore: false,
          }));
        } else if (query === "cross" && page === "1") {
          response.end(issueBody(90, "Cross-page first", true));
        } else if (query === "cross" && page === "2") {
          response.end(issueBody(90, "Cross-page duplicate"));
        } else if (query === "lean" && page === "1") {
          response.end(issueBody(
            1,
            "<img src=x onerror=\"globalThis.issueXss=true\">",
            true,
          ));
        } else if (query === "lean" && page === "2") {
          response.end(issueBody(2, "Second page issue"));
        } else {
          response.end(issueBody(80, `Query ${query}`));
        }
      } else if (requested === "") {
        response.setHeader("content-type", "text/html; charset=utf-8");
        response.end("<!doctype html><html lang=\"en\"><head><title>Issue Browser</title></head><body><div id=\"app\"></div></body></html>");
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

test("loads, paginates, retries, suppresses stale HTTP, and cancels disposal", async ({ page }) => {
  const pageErrors = [];
  page.on("pageerror", (error) => pageErrors.push(error.message));
  await page.goto(origin);
  const expected = await page.evaluate(async () =>
    (await fetch("/IssueBrowser.expected.json")).json(),
  );
  await page.evaluate(async () => {
    const { mount } = await import("/IssueBrowser.mjs");
    globalThis.issueDispose = mount(document.getElementById("app"));
  });

  const root = page.locator(".leanrx-issues");
  const input = root.getByRole("textbox", { name: "Issue query" });
  const search = root.getByRole("button", { name: "Search" });
  const next = root.getByRole("button", { name: "Next page" });
  const retry = root.getByRole("button", { name: "Retry" });
  const status = root.getByRole("status");
  const issues = root.getByRole("list", { name: "Issues" }).getByRole("listitem");

  await expect(status).toHaveText(expected.loadedStatus);
  await expect(issues).toHaveCount(1);
  await expect(issues.first()).toHaveText(expected.firstIssue.title);
  await expect(root.locator("img")).toHaveCount(0);
  expect(await page.evaluate(() => globalThis.issueXss)).toBeUndefined();
  expect(await page.evaluate(() => globalThis.issueHeadingXss)).toBeUndefined();
  expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);

  await input.focus();
  await input.press("Tab");
  await expect(search).toBeFocused();
  await search.press("Enter");
  await expect(status).toHaveText("Loaded 1 issues");

  await next.click();
  await expect(status).toHaveText("Loaded 2 issues");
  await expect(issues).toHaveCount(2);
  await expect(issues.nth(1)).toHaveText("Second page issue");
  await expect(next).toBeDisabled();

  await input.fill("bad");
  await expect(status).toContainText("Request failed: issue response decode failed");
  await expect(retry).toBeEnabled();

  await input.fill("failure");
  await expect(status).toHaveText(expected.httpFailureStatus);
  await retry.click();
  await expect(status).toHaveText("Loaded 1 issues");
  await expect(issues.first()).toHaveText("Recovered issue");

  await input.fill("duplicate");
  await expect(status).toContainText("Request failed: issue response contains duplicate IDs");
  await expect(issues.first()).toHaveText("Recovered issue");
  expect(pageErrors).toEqual([]);

  await input.fill("cross");
  await expect(status).toHaveText("Loaded 1 issues");
  await expect(issues.first()).toHaveText("Cross-page first");
  await next.click();
  await expect(status).toContainText("Request failed: issue response contains duplicate IDs");
  await expect(issues).toHaveCount(1);
  await expect(issues.first()).toHaveText("Cross-page first");
  expect(pageErrors).toEqual([]);

  await input.fill("slow");
  await expect(status).toHaveText("Loading");
  await input.fill("fresh");
  await expect(status).toHaveText("Loaded 1 issues");
  await expect(issues.first()).toHaveText("Query fresh");
  await page.waitForTimeout(400);
  await expect(issues.first()).toHaveText("Query fresh");

  await input.fill("a&b=?");
  await expect(issues.first()).toHaveText("Query a&b=?");
  expect(requests.some(({ query, page: requestedPage }) =>
    query === "a&b=?" && requestedPage === "1")).toBe(true);

  await input.fill("slow-dispose");
  await expect(status).toHaveText("Loading");
  await page.evaluate(() => globalThis.issueDispose());
  await expect(root).toHaveCount(0);
  await page.waitForTimeout(400);
  expect(await page.evaluate(() => globalThis.issueDispose.effectInstrumentation()))
    .toEqual([13, 2]);
  expect(await page.evaluate(() => globalThis.issueDispose.instrumentation().slice(8, 10)))
    .toEqual([13, 2]);
  expect(pageErrors).toEqual([]);
});
