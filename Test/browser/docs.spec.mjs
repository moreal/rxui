import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const directory = process.env.LEANRX_DOCS_DIST;
if (!directory) throw new Error("LEANRX_DOCS_DIST is required");

const files = new Set([
  "index.html",
  "styles.css",
  "LeanRxDocs.mjs",
  "LeanRxDocs.graph.html",
  "leanrx-docs.json",
  "leanrx_dom.mjs",
  "docs/guides/getting-started.md",
  "docs/guides/philosophy.md",
  "docs/guides/components.md",
  "docs/guides/integrations.md",
  "docs/guides/language.md",
  "docs/guides/backend-support.md",
  "docs/guides/trust-model.md",
  "DOGFOOD.md",
]);
let server;
let origin;

test.beforeAll(async () => {
  server = createServer(async (request, response) => {
    try {
      const requested = new URL(request.url, "http://localhost").pathname.slice(1) ||
        "index.html";
      if (!files.has(requested)) {
        response.statusCode = 404;
        response.end("not found");
        return;
      }
      response.setHeader("content-type",
        requested.endsWith(".mjs") ? "text/javascript; charset=utf-8" :
          requested.endsWith(".css") ? "text/css; charset=utf-8" :
            requested.endsWith(".json") ? "application/json; charset=utf-8" :
              requested.endsWith(".md") ? "text/markdown; charset=utf-8" :
                "text/html; charset=utf-8");
      response.end(await readFile(path.join(directory, requested)));
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

test("dogfoods seven useful pages with active navigation and exact work", async ({ page }) => {
  await page.goto(origin);
  const title = page.locator("main h1");
  const body = page.locator("article section").first().locator("p");
  const code = page.locator("pre code");
  const buttons = page.locator("nav button");
  await expect(title).toHaveText("Build a checked browser component");
  await expect(code).toContainText("leanrx -- doctor");
  await expect(buttons).toHaveCount(7);
  await expect(buttons.nth(0)).toHaveAttribute("aria-pressed", "true");
  expect(await buttons.evaluateAll((values) =>
    values.every((value) => value.getAttribute("type") === "button"),
  )).toBe(true);

  const destinations = [
    "Make frontend behavior inspectable",
    "Dependencies are data, not runtime guesses",
    "Write a small staged component",
    "Tailwind works as a build-time compiler",
    "A small Lean-native kit, not shadcn/ui",
    "Know what LeanRx cannot do yet",
  ];
  await buttons.nth(1).focus();
  await expect(buttons.nth(1)).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(title).toHaveText(destinations[0]);
  await expect(buttons.nth(1)).toHaveAttribute("aria-pressed", "true");
  for (let index = 2; index < 7; index += 1) {
    await buttons.nth(index).click();
    await expect(title).toHaveText(destinations[index - 1]);
    await expect(buttons.nth(index)).toHaveAttribute("aria-pressed", "true");
    await expect(buttons.nth(index - 1)).toHaveAttribute("aria-pressed", "false");
  }
  await expect(body).toContainText("no general URL router");
  await buttons.nth(3).click();
  await expect(code).toContainText("component Counter");
  await expect(code.locator("main")).toHaveCount(0);
  await buttons.nth(0).click();
  await expect(title).toHaveText("Build a checked browser component");

  const instrumentation = await page.evaluate(() =>
    globalThis.leanrxDocsDispose.instrumentation(),
  );
  expect(instrumentation.slice(0, 7)).toEqual([0, 8, 8, 48, 48, 48, 48]);
  expect(instrumentation[7].filter((entry) => entry === "transaction:commit")).toHaveLength(8);
  expect(instrumentation[7].filter((entry) => entry.endsWith(":write"))).toHaveLength(88);

  const layout = await page.evaluate(() => {
    const shell = document.querySelector("header + div");
    const nav = document.querySelector("nav");
    const root = document.querySelector("#app > div");
    return {
      shellDisplay: getComputedStyle(shell).display,
      shellColumns: getComputedStyle(shell).gridTemplateColumns,
      navDisplay: getComputedStyle(nav).display,
      background: getComputedStyle(root).backgroundColor,
    };
  });
  expect(layout.shellDisplay).toBe("grid");
  expect(layout.shellColumns).not.toBe("none");
  expect(layout.navDisplay).toBe("grid");
  expect(layout.background).not.toBe("rgba(0, 0, 0, 0)");

  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);

  const integrations = await (
    await page.request.get(`${origin}/docs/guides/integrations.md`)
  ).text();
  expect(integrations).toContain("Tailwind CSS: tested");
  expect(integrations).toContain("shadcn/ui: not directly compatible");
  const metadata = await (await page.request.get(`${origin}/leanrx-docs.json`)).json();
  expect(metadata).toMatchObject({
    framework: "LeanRx.Docs",
    shadcnDirectCompatibility: false,
    markdownExport: true,
  });

  const graphHtml = await (await page.request.get(`${origin}/LeanRxDocs.graph.html`)).text();
  expect(graphHtml).toContain("<!doctype html>");
  expect(graphHtml).toContain("Certified schedule");
  expect(graphHtml).not.toContain("<script");

  await page.goto(`${origin}/LeanRxDocs.graph.html`);
  await expect(page.locator("main h1")).toHaveText("LeanRx reactive graph");
  await expect(page.locator(".leanrx-node")).toHaveCount(27);
  const graphAccessibility = await new AxeBuilder({ page }).analyze();
  expect(graphAccessibility.violations).toEqual([]);
});

test("keeps the Tailwind layout usable on a narrow viewport", async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto(origin);
  const nav = page.locator("nav");
  const first = nav.locator("button").first();
  await expect(first).toBeVisible();
  const metrics = await nav.evaluate((node) => {
    const button = node.querySelector("button");
    return {
      columns: getComputedStyle(node).gridTemplateColumns.split(" ").length,
      buttonHeight: button.getBoundingClientRect().height,
      overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    };
  });
  expect(metrics.columns).toBe(2);
  expect(metrics.buttonHeight).toBeGreaterThanOrEqual(44);
  expect(metrics.overflow).toBe(0);
});

test("keeps the dark theme accessible and honors reduced motion", async ({ page }) => {
  await page.emulateMedia({ colorScheme: "dark", reducedMotion: "reduce" });
  await page.goto(origin);
  const theme = await page.evaluate(() => ({
    colorScheme: getComputedStyle(document.documentElement).colorScheme,
    scrollBehavior: getComputedStyle(document.documentElement).scrollBehavior,
    background: getComputedStyle(document.querySelector("#app > div")).backgroundColor,
  }));
  expect(theme.colorScheme).toBe("dark");
  expect(theme.scrollBehavior).toBe("auto");
  expect(theme.background).not.toBe("rgba(0, 0, 0, 0)");
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("mounts independently and disposes listeners idempotently", async ({ page }) => {
  await page.goto(origin);
  const result = await page.evaluate(async () => {
    const second = document.createElement("div");
    second.id = "second";
    document.body.append(second);
    const { mount } = await import("/LeanRxDocs.mjs");
    const disposeSecond = mount(second);
    const firstButton = document.querySelector("#app nav button");
    const secondButton = document.querySelector("#second nav button:nth-of-type(2)");
    secondButton.click();
    const firstTitle = document.querySelector("#app h1").textContent;
    const secondTitle = document.querySelector("#second h1").textContent;
    const before = disposeSecond.instrumentation();
    disposeSecond();
    disposeSecond();
    secondButton.click();
    const after = disposeSecond.instrumentation();
    globalThis.leanrxDocsDispose();
    globalThis.leanrxDocsDispose();
    firstButton.click();
    return { firstTitle, secondTitle, before, after };
  });
  expect(result.firstTitle).toBe("Build a checked browser component");
  expect(result.secondTitle).toBe("Make frontend behavior inspectable");
  expect(result.after).toEqual(result.before);
  await expect(page.locator("#app > div")).toHaveCount(0);
});
