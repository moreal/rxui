/**
 * The host-side order contract (ADR-0094).
 *
 * ADR-0093 audits every module the component backend emits for the shapes that
 * could disturb a region's row table, and stops at the call boundary: its R1
 * lets a table reach `createKeyedRegion`'s handle and `$lrx_row_seek`, and
 * nothing on the far side of that call was checked. `runtime/leanrx_region.mjs`
 * takes the caller's array at `update(items, …)`, one of its rows at
 * `updateAt(…, row, …)` and the target order at `swapAt(…, items, …)`, and it
 * holds a `splice`, a two-slot exchange and a positional removal internally. In
 * the source `current.splice(index, 1)` and `items.splice(index, 1)` are the
 * same shape; only what the identifier is bound to says whether the host
 * disturbed its own entry array or the caller's table, and that is a question
 * no rule over the host's text answers.
 *
 * This module answers it by running. Four rules, one code, `LRX-HOST-001`:
 *
 * H1 — every array a caller hands a region host crosses the boundary as a
 *      frozen copy and stays frozen for the life of the process, so a `push`,
 *      `splice`, `sort`, `reverse` or element assignment throws inside the host
 *      call whether it happens now or three calls later through a reference the
 *      host stashed. Element identity is re-verified as well, so a bypass that
 *      does not throw is still observed. The primitives that would mutate
 *      silently instead of throwing (`Reflect.*`, `defineProperty`) are banned
 *      in the host sources by `scripts/check_region_runtime.sh`.
 * H2 — the key slot of every row a host is handed is snapshotted and
 *      re-verified after every later call. Rows deliberately cross *unfrozen*:
 *      a host forwards them to generated callbacks that own their other slots
 *      (the ADR-0085/0086 per-row caches), and only slot 0 is the order's
 *      business.
 * H3 — the handle surface is closed. A method the contract cannot classify, or
 *      one it classifies that the handle no longer exports, fails here — so a
 *      new host export has to declare which of its arguments are caller arrays,
 *      which is the same event that bumps `runtimeAbi`.
 * H4 — every array-taking entry point of every region host must actually be
 *      exercised under the guard. A neutered guard cannot pass quietly.
 *
 * The guard hands over a *copy* rather than freezing the caller's own array,
 * because both caller shapes reuse their array across calls: the component
 * backend pushes onto `regions[r][1]` between transactions, and the
 * hand-written js-framework-benchmark splices its own rows around `swapAt` and
 * `removeAt`. Every row object keeps its identity across the copy, which is
 * what the host's entry cache and the mount/update callbacks see.
 */

const NOT_A_ROW = Symbol("not a row");

/** For each host, the exact handle surface and which arguments are caller
 * arrays: a `table` of rows, a single `row`, a `batch` of tagged deltas, or an
 * opaque `list`. An empty record is a method that takes no caller array; it is
 * still wrapped, because it still triggers a sweep. */
const SURFACE = {
  keyed: {
    update: { 0: "table" },
    updateAt: { 1: "row" },
    swapAt: { 2: "table" },
    removeAt: {},
    instrumentation: {},
    dispose: {},
  },
  delta: {
    update: { 0: "table" },
    apply: { 0: "batch" },
    instrumentation: {},
    dispose: {},
  },
  positional: { update: { 0: "list" }, instrumentation: {}, dispose: {} },
  conditional: { update: {}, instrumentation: {}, dispose: {} },
};

const live = [];
const exercised = new Set();
let handedOver = 0;
let sweeps = 0;

function fail(rule, subject, detail) {
  throw new Error(`LRX-HOST-001 host order contract (${rule}) at ${subject}: ${detail}`);
}

function show(value) {
  if (typeof value === "string") return JSON.stringify(value);
  return typeof value === "object" && value !== null ? "[object]" : String(value);
}

function registerFrozen(kind, method, source, keys) {
  const array = Object.freeze(source.slice());
  live.push({ kind, method, array, cells: source.slice(), keys });
  handedOver += 1;
  return array;
}

function registerTable(kind, method, source) {
  return registerFrozen(kind, method, source,
    source.map((row) => (Array.isArray(row) ? row[0] : NOT_A_ROW)));
}

function registerList(kind, method, source) {
  return registerFrozen(kind, method, source, null);
}

function registerRow(kind, method, row) {
  live.push({ kind, method, row, key: row[0], width: row.length });
  handedOver += 1;
  return row;
}

/** A delta batch is one level deeper than a table: the batch and each tagged
 * delta are the host's to read, a `reset` carries a table, and the row a delta
 * carries is forwarded to a callback, so it crosses unfrozen like any row. */
function registerBatch(kind, method, source) {
  const deltas = source.map((delta) => {
    if (!Array.isArray(delta)) return delta;
    const copy = delta.slice();
    if (copy[0] === "reset" && Array.isArray(copy[1])) {
      copy[1] = registerTable(kind, method, copy[1]);
    }
    return registerList(kind, method, copy);
  });
  return registerList(kind, method, deltas);
}

function hand(kind, method, kindOfArgument, value) {
  if (!Array.isArray(value)) return value;
  if (kindOfArgument === "table") return registerTable(kind, method, value);
  if (kindOfArgument === "row") return registerRow(kind, method, value);
  if (kindOfArgument === "batch") return registerBatch(kind, method, value);
  return registerList(kind, method, value);
}

/** Re-verify every array ever handed to a host. Runs after every call — the
 * point of keeping retired guards live is that a host which stashes the array
 * it was given and disturbs it on a later call is caught on that later call. */
function sweep() {
  for (const guard of live) {
    const subject = `${guard.kind}.${guard.method}`;
    if (guard.row !== undefined) {
      if (guard.row.length !== guard.width) {
        fail("H2", subject, "the row it was handed changed length");
      }
      if (!Object.is(guard.row[0], guard.key)) {
        fail("H2", subject, `the row it was handed changed its key from ` +
          `${show(guard.key)} to ${show(guard.row[0])}`);
      }
      continue;
    }
    if (guard.array.length !== guard.cells.length) {
      fail("H1", subject, `the array it was handed changed length from ` +
        `${guard.cells.length} to ${guard.array.length}`);
    }
    for (let index = 0; index < guard.cells.length; index += 1) {
      if (!Object.is(guard.array[index], guard.cells[index])) {
        fail("H1", subject,
          `the array it was handed holds a different element at position ${index}`);
      }
    }
    if (guard.keys === null) continue;
    for (let index = 0; index < guard.keys.length; index += 1) {
      const row = guard.array[index];
      const key = Array.isArray(row) ? row[0] : NOT_A_ROW;
      if (!Object.is(key, guard.keys[index])) {
        fail("H2", subject, `the row at position ${index} of the array it was ` +
          `handed changed its key from ${show(guard.keys[index])} to ${show(key)}`);
      }
    }
  }
  sweeps += 1;
}

/** Wrap one region handle. `kind` names which host built it, because the
 * conditional and positional handles are otherwise indistinguishable. */
export function guardHost(kind, region) {
  const surface = SURFACE[kind];
  if (surface === undefined) {
    fail("H3", `${kind}.*`, "the contract does not know this region host");
  }
  for (const name of Object.keys(region)) {
    if (!Object.hasOwn(surface, name)) {
      fail("H3", `${kind}.${name}`,
        "the handle exports a method the contract does not classify; declare which " +
        "of its arguments are caller arrays (a new host export bumps runtimeAbi)");
    }
  }
  const guarded = {};
  for (const [name, positions] of Object.entries(surface)) {
    if (typeof region[name] !== "function") {
      fail("H3", `${kind}.${name}`,
        "the contract classifies a method the handle does not export");
    }
    guarded[name] = (...args) => {
      exercised.add(`${kind}.${name}`);
      const passed = args.map((value, index) =>
        (positions[index] === undefined ? value : hand(kind, name, positions[index], value)));
      try {
        return region[name](...passed);
      } finally {
        sweep();
      }
    };
  }
  return guarded;
}

/** H4. Called once at the end of the region gate. */
export function assertHostContractExercised() {
  sweep();
  const required = [];
  for (const [kind, surface] of Object.entries(SURFACE)) {
    for (const [name, positions] of Object.entries(surface)) {
      if (Object.keys(positions).length > 0) required.push(`${kind}.${name}`);
    }
  }
  const missing = required.filter((entry) => !exercised.has(entry));
  if (missing.length > 0) {
    fail("H4", "the region hosts",
      `these array-taking entry points were never exercised under the guard: ${missing.join(", ")}`);
  }
  if (handedOver === 0 || sweeps === 0) {
    fail("H4", "the region hosts", "the guard never intercepted a caller array");
  }
  console.log(`host order contract: ${handedOver} arrays guarded across ` +
    `${required.length} array-taking entry points, ${sweeps} sweeps`);
}
