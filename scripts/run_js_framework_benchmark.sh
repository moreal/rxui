#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
upstream_directory="$repository_root/.tmp/js-framework-benchmark"
headless=false
smoke=false
build_results=true

while (( $# > 0 )); do
  case "$1" in
    --headless)
      headless=true
      shift
      ;;
    --smoke)
      smoke=true
      shift
      ;;
    --no-results)
      build_results=false
      shift
      ;;
    --help|-h)
      echo "usage: $0 [--headless] [--smoke] [--no-results] [upstream-directory]"
      exit 0
      ;;
    --*)
      echo "unknown option: $1" >&2
      exit 2
      ;;
    *)
      upstream_directory="$1"
      shift
      if (( $# > 0 )); then
        echo "only one upstream directory may be supplied" >&2
        exit 2
      fi
      ;;
  esac
done

"$repository_root/scripts/prepare_js_framework_benchmark.sh" "$upstream_directory"

if [[ ! -d "$upstream_directory/node_modules" ]] ||
    [[ ! -f "$upstream_directory/webdriver-ts/dist/benchmarkRunner.js" ]] ||
    [[ ! -d "$upstream_directory/server/node_modules" ]]; then
  echo "benchmark dependencies are missing" >&2
  echo "run: ./scripts/prepare_js_framework_benchmark.sh --install \"$upstream_directory\"" >&2
  exit 1
fi

server_log="$repository_root/.tmp/js-framework-benchmark-server.log"
mkdir -p "$(dirname "$server_log")"
(
  cd "$upstream_directory"
  npm start
) >"$server_log" 2>&1 &
server_pid=$!

cleanup() {
  if kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

ready=false
for _attempt in $(seq 1 60); do
  if curl --silent --fail http://127.0.0.1:8080/ls >/dev/null; then
    ready=true
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  echo "benchmark server did not become ready; see $server_log" >&2
  tail -n 80 "$server_log" >&2 || true
  exit 1
fi

keyed_args=(--framework keyed/leanrx)
csp_args=(keyed/leanrx)
benchmark_args=(--framework keyed/vanillajs keyed/leanrx)
if [[ "$headless" == true ]]; then
  keyed_args+=(--headless)
  csp_args+=(--headless)
  benchmark_args+=(--headless)
fi
if [[ -n "${LEANRX_BENCH_CHROME_BINARY:-}" ]]; then
  keyed_args+=(--chromeBinary "$LEANRX_BENCH_CHROME_BINARY")
  csp_args+=(--chromeBinary "$LEANRX_BENCH_CHROME_BINARY")
  benchmark_args+=(--chromeBinary "$LEANRX_BENCH_CHROME_BINARY")
fi

(
  cd "$upstream_directory/webdriver-ts"
  npm run isKeyed -- "${keyed_args[@]}"
  # chrome150's CSP checker only applies its filter to positional arguments.
  npm run checkCSP -- "${csp_args[@]}"
)

if [[ "$smoke" == true ]]; then
  benchmark_args+=(--smoketest)
elif [[ -n "${LEANRX_BENCH_COUNT:-}" ]]; then
  benchmark_args+=(--count "$LEANRX_BENCH_COUNT")
fi

mkdir -p "$upstream_directory/webdriver-ts/results"
find "$upstream_directory/webdriver-ts/results" -maxdepth 1 -type f -name '*.json' -delete
if [[ -d "$upstream_directory/webdriver-ts/traces" ]]; then
  find "$upstream_directory/webdriver-ts/traces" -maxdepth 1 -type f -name '*.json' -delete
fi

(
  cd "$upstream_directory"
  npm run bench -- "${benchmark_args[@]}"
  if [[ "$smoke" == false && "$build_results" == true ]]; then
    npm run results
  fi
)

if [[ "$smoke" == false ]]; then
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  results_root="${LEANRX_BENCH_RESULTS_DIR:-$repository_root/.tmp/js-framework-benchmark-results}"
  results_directory="$results_root/$timestamp"
  mkdir -p "$results_directory"
  cp -R "$upstream_directory/webdriver-ts/results" "$results_directory/raw"
  cp -R "$upstream_directory/frameworks/keyed/leanrx" "$results_directory/framework"
  if [[ -d "$upstream_directory/webdriver-ts/traces" ]]; then
    cp -R "$upstream_directory/webdriver-ts/traces" "$results_directory/traces"
  fi
  if [[ "$build_results" == true && -d "$upstream_directory/webdriver-ts-results/dist" ]]; then
    cp -R "$upstream_directory/webdriver-ts-results/dist" "$results_directory/table"
  fi
  if [[ -z "$(git -C "$repository_root" status --short)" ]]; then
    tree_state="clean"
  else
    tree_state="dirty"
  fi
  git -C "$repository_root" status --short >"$results_directory/repository-status.txt"
  git -C "$repository_root" diff --binary HEAD >"$results_directory/repository-changes.patch"
  {
    echo "measuredAtUtc=$timestamp"
    echo "leanrxCommit=$(git -C "$repository_root" rev-parse HEAD)"
    echo "leanrxTreeState=$tree_state"
    echo "benchmarkCommit=$(git -C "$upstream_directory" rev-parse HEAD)"
    echo "uname=$(uname -a)"
    echo "node=$(node --version)"
    echo "npm=$(npm --version)"
    echo "lean=$(lean --version | head -n 1)"
    echo "lake=$(lake --version | head -n 1)"
    echo "headless=$headless"
    echo "chromeBinary=${LEANRX_BENCH_CHROME_BINARY:-default}"
    echo "count=${LEANRX_BENCH_COUNT:-upstream-default}"
  } >"$results_directory/environment.txt"
  echo "archived framework, raw results, traces, and environment metadata in $results_directory"
fi
