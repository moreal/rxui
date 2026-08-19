import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./Test/browser",
  fullyParallel: false,
  workers: 1,
  reporter: "line",
  use: {
    browserName: "chromium",
    headless: true,
  },
});
