#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
upstream_directory="$repository_root/.tmp/js-framework-benchmark"
headless=false
smoke=false
build_results=true
preset="popular"
framework_arguments=()
benchmark_arguments=()

usage() {
  cat <<'EOF'
usage: scripts/run_js_framework_benchmark.sh [options] [upstream-directory]

options:
  --preset popular     LeanRx, vanilla, React Hooks, Preact, Vue, Solid, Svelte (default)
  --preset baseline    LeanRx and vanilla only
  --preset all-keyed   all upstream keyed implementations plus LeanRx
  --preset all         all upstream keyed and non-keyed implementations plus LeanRx
  --framework NAME     custom comparison; repeat as needed (LeanRx is always added)
  --benchmark ID       run matching upstream workload IDs; repeat as needed
  --cpu                 run the nine CPU workloads
  --memory              run the three memory workloads
  --size                run size and first-paint workloads
  --headless           use headless Chrome (local/CI diagnostics only)
  --smoke              one validation iteration; does not write measurements
  --no-results         skip building the interactive upstream results site
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --preset)
      if (( $# < 2 )); then
        echo "--preset requires a value" >&2
        exit 2
      fi
      preset="$2"
      shift 2
      ;;
    --framework)
      if (( $# < 2 )); then
        echo "--framework requires a keyed/name or non-keyed/name" >&2
        exit 2
      fi
      framework_arguments+=("$2")
      shift 2
      ;;
    --benchmark)
      if (( $# < 2 )); then
        echo "--benchmark requires a workload ID or prefix" >&2
        exit 2
      fi
      benchmark_arguments+=("$2")
      shift 2
      ;;
    --cpu)
      benchmark_arguments+=(01_ 02_ 03_ 04_ 05_ 06_ 07_ 08_ 09_)
      shift
      ;;
    --memory)
      benchmark_arguments+=(21_ 22_ 25_)
      shift
      ;;
    --size)
      benchmark_arguments+=(40_)
      shift
      ;;
    --all-keyed)
      preset="all-keyed"
      shift
      ;;
    --all)
      preset="all"
      shift
      ;;
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
    --)
      shift
      ;;
    --help|-h)
      usage
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

case "$preset" in
  popular|baseline|all-keyed|all) ;;
  *)
    echo "unknown preset: $preset" >&2
    usage >&2
    exit 2
    ;;
esac

if (( ${#framework_arguments[@]} > 0 )); then
  preset="custom"
  selected_frameworks=("${framework_arguments[@]}")
  if [[ " ${selected_frameworks[*]} " != *" keyed/leanrx "* ]]; then
    selected_frameworks+=(keyed/leanrx)
  fi
else
  case "$preset" in
    popular)
      selected_frameworks=(
        keyed/vanillajs
        keyed/react-hooks
        keyed/preact-hooks
        keyed/vue
        keyed/solid
        keyed/svelte
        keyed/leanrx
      )
      ;;
    baseline)
      selected_frameworks=(keyed/vanillajs keyed/leanrx)
      ;;
    all-keyed|all)
      selected_frameworks=()
      ;;
  esac
fi

prepare_args=()
needs_prebuilt=false
if [[ "$preset" == all-keyed || "$preset" == all ]]; then
  needs_prebuilt=true
else
  for framework in "${selected_frameworks[@]}"; do
    if [[ "$framework" != keyed/leanrx && "$framework" != keyed/vanillajs ]]; then
      needs_prebuilt=true
      break
    fi
  done
fi
if [[ "$needs_prebuilt" == true ]]; then
  prepare_args+=(--prebuilt)
fi
"$repository_root/scripts/prepare_js_framework_benchmark.sh" "${prepare_args[@]}" "$upstream_directory"

for framework in "${selected_frameworks[@]}"; do
  if [[ ! "$framework" =~ ^(keyed|non-keyed)/[A-Za-z0-9._-]+$ ]]; then
    echo "invalid framework name: $framework" >&2
    exit 2
  fi
  if [[ ! -f "$upstream_directory/frameworks/$framework/package.json" ]]; then
    echo "framework not found in pinned upstream release: $framework" >&2
    exit 2
  fi
done

if [[ ! -d "$upstream_directory/node_modules" ]] ||
    [[ ! -f "$upstream_directory/webdriver-ts/dist/benchmarkRunner.js" ]] ||
    [[ ! -d "$upstream_directory/server/node_modules" ]]; then
  echo "benchmark dependencies are missing; installing them once"
  "$repository_root/scripts/prepare_js_framework_benchmark.sh" \
    --install "${prepare_args[@]}" "$upstream_directory"
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

if (( ${#selected_frameworks[@]} > 0 )); then
  validation_frameworks=("${selected_frameworks[@]}")
  benchmark_args=(--framework "${selected_frameworks[@]}")
elif [[ "$preset" == all-keyed ]]; then
  # The release implementations are already validated upstream. Rechecking every
  # implementation would add hours before the actual benchmark.
  validation_frameworks=(keyed/leanrx)
  benchmark_args=(--type keyed)
else
  validation_frameworks=(keyed/leanrx)
  benchmark_args=()
fi
keyed_args=(--framework "${validation_frameworks[@]}")
csp_args=("${validation_frameworks[@]}")
if (( ${#benchmark_arguments[@]} > 0 )); then
  benchmark_args+=(--benchmark "${benchmark_arguments[@]}")
fi
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
    echo "preset=$preset"
    if (( ${#selected_frameworks[@]} > 0 )); then
      printf 'frameworks=%s\n' "${selected_frameworks[*]}"
    else
      echo "frameworks=$preset"
    fi
    if (( ${#benchmark_arguments[@]} > 0 )); then
      printf 'benchmarks=%s\n' "${benchmark_arguments[*]}"
    else
      echo "benchmarks=upstream-default"
    fi
  } >"$results_directory/environment.txt"
  echo "archived framework, raw results, traces, and environment metadata in $results_directory"
fi
