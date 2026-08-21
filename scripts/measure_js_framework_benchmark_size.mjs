import { brotliCompressSync, gzipSync } from "node:zlib";
import { readFile } from "node:fs/promises";
import path from "node:path";

const directory = process.argv[2];
if (!directory) {
  throw new Error(
    "usage: node scripts/measure_js_framework_benchmark_size.mjs <dist> [baseline.json]",
  );
}
const baselinePath = process.argv[3];

const manifestPath = path.join(directory, "benchmark-assets.json");
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
if (!Array.isArray(manifest.files) || manifest.files.length === 0) {
  throw new Error("benchmark-assets.json must contain a non-empty files array");
}

const files = [];
for (const name of manifest.files) {
  if (typeof name !== "string" || path.basename(name) !== name) {
    throw new Error(`unsafe benchmark asset name: ${String(name)}`);
  }
  const contents = await readFile(path.join(directory, name));
  const rawBytes = contents.byteLength;
  // chrome150's server leaves responses below 1 KiB uncompressed and calls
  // zlib.brotliCompressSync with its defaults for larger responses.
  const brotliBytes = rawBytes >= 1024 ? brotliCompressSync(contents).byteLength : rawBytes;
  const gzipBytes = gzipSync(contents, { level: 9 }).byteLength;
  files.push({ name, rawBytes, brotliBytes, gzipBytes });
}

const sum = (field) => files.reduce((total, file) => total + file[field], 0);
const report = {
  schemaVersion: 1,
  upstreamTag: "chrome150",
  upstreamCommit: "fa15a77d73dca6dfc0a97ce8c4d6c0797726fa75",
  commonCssExcluded: true,
  brotliThresholdBytes: 1024,
  files,
  totals: {
    rawBytes: sum("rawBytes"),
    brotliBytes: sum("brotliBytes"),
    gzipBytes: sum("gzipBytes"),
  },
};

const rendered = `${JSON.stringify(report, null, 2)}\n`;
process.stdout.write(rendered);

if (baselinePath) {
  const baseline = JSON.parse(await readFile(baselinePath, "utf8"));
  if (JSON.stringify(baseline) !== JSON.stringify(report)) {
    const rawDelta = report.totals.rawBytes - baseline.totals.rawBytes;
    const brotliDelta = report.totals.brotliBytes - baseline.totals.brotliBytes;
    throw new Error(
      `size baseline changed: raw ${rawDelta >= 0 ? "+" : ""}${rawDelta} bytes, ` +
      `brotli ${brotliDelta >= 0 ? "+" : ""}${brotliDelta} bytes; ` +
      "review the artifacts and update bench/js-framework-benchmark-size-baseline.json",
    );
  }
}
