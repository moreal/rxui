#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$repository_root/Test/fixtures/js-framework-benchmark"
workspace="$(mktemp -d)"
trap 'rm -rf -- "$workspace"' EXIT

fail() {
  echo "JS framework benchmark script test failed: $*" >&2
  exit 1
}

assert_contains() {
  local text="$1"
  local expected="$2"
  if [[ "$text" != *"$expected"* ]]; then
    fail "missing expected text: $expected"
  fi
}

assert_not_contains() {
  local text="$1"
  local unexpected="$2"
  if [[ "$text" == *"$unexpected"* ]]; then
    fail "found unexpected text: $unexpected"
  fi
}

make_fake_bin() {
  local directory="$1"
  shift
  mkdir -p "$directory"
  for tool in "$@"; do
    ln -s "$fixture_root/fake_tool.sh" "$directory/$tool"
  done
}

expect_failure() {
  local expected_status="$1"
  local expected_text="$2"
  shift 2
  local output
  local status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -ne "$expected_status" ]]; then
    fail "expected exit $expected_status, got $status: $output"
  fi
  assert_contains "$output" "$expected_text"
}

harness="$workspace/runner-harness"
fake_bin="$harness/fake-bin"
log="$harness/calls.log"
upstream="$harness/upstream"
mkdir -p "$harness/scripts"
cp "$repository_root/scripts/run_js_framework_benchmark.sh" "$harness/scripts/"
cp "$fixture_root/fake_prepare.sh" "$harness/scripts/prepare_js_framework_benchmark.sh"
chmod +x "$harness/scripts/"*.sh
make_fake_bin "$fake_bin" npm curl git lake
: >"$log"

runner="$harness/scripts/run_js_framework_benchmark.sh"
runner_env=(
  "PATH=$fake_bin:$PATH"
  "LEANRX_BENCH_TEST_LOG=$log"
)

run_runner() {
  : >"$log"
  if ! runner_output="$(env "${runner_env[@]}" "$runner" "$@" 2>&1)"; then
    fail "runner unexpectedly failed: $runner_output"
  fi
  runner_calls="$(<"$log")"
}

popular_frameworks="keyed/vanillajs keyed/react-hooks keyed/preact-hooks keyed/vue keyed/solid keyed/svelte keyed/leanrx"
run_runner --smoke "$upstream"
assert_contains "$runner_calls" "prepare|--prebuilt $upstream"
assert_contains "$runner_calls" "npm|run isKeyed -- --framework $popular_frameworks"
assert_contains "$runner_calls" "npm|run checkCSP -- $popular_frameworks"
assert_contains "$runner_calls" "npm|run bench -- --framework $popular_frameworks --smoketest"

export LEANRX_BENCH_CHROME_BINARY="/fixture/chrome"
run_runner --preset baseline --cpu --headless --smoke "$upstream"
unset LEANRX_BENCH_CHROME_BINARY
assert_contains "$runner_calls" "prepare|$upstream"
assert_not_contains "$runner_calls" "prepare|--prebuilt"
assert_contains "$runner_calls" \
  "npm|run isKeyed -- --framework keyed/vanillajs keyed/leanrx --headless --chromeBinary /fixture/chrome"
assert_contains "$runner_calls" \
  "npm|run bench -- --framework keyed/vanillajs keyed/leanrx --benchmark 01_ 02_ 03_ 04_ 05_ 06_ 07_ 08_ 09_ --headless --chromeBinary /fixture/chrome --smoketest"

run_runner --framework non-keyed/vanillajs --benchmark 05_ --memory --size --smoke "$upstream"
assert_contains "$runner_calls" "prepare|--prebuilt $upstream"
assert_contains "$runner_calls" \
  "npm|run bench -- --framework non-keyed/vanillajs keyed/leanrx --benchmark 05_ 21_ 22_ 25_ 40_ --smoketest"

run_runner --all-keyed --smoke "$upstream"
assert_contains "$runner_calls" "npm|run isKeyed -- --framework keyed/leanrx"
assert_contains "$runner_calls" "npm|run bench -- --type keyed --smoketest"

run_runner --all --smoke "$upstream"
assert_contains "$runner_calls" "npm|run isKeyed -- --framework keyed/leanrx"
assert_contains "$runner_calls" "npm|run bench -- --smoketest"

results_root="$harness/results-no-table"
runner_env+=("LEANRX_BENCH_RESULTS_DIR=$results_root")
run_runner --preset baseline --no-results "$upstream"
assert_not_contains "$runner_calls" "npm|run results"
environment_file="$(find "$results_root" -name environment.txt -print -quit)"
[[ -n "$environment_file" ]] || fail "runner did not archive environment metadata"
environment="$(<"$environment_file")"
assert_contains "$environment" "preset=baseline"
assert_contains "$environment" "frameworks=keyed/vanillajs keyed/leanrx"

results_root="$harness/results-with-table"
runner_env[2]="LEANRX_BENCH_RESULTS_DIR=$results_root"
run_runner --preset baseline "$upstream"
assert_contains "$runner_calls" "npm|run results"
[[ -n "$(find "$results_root" -path '*/table/index.html' -print -quit)" ]] ||
  fail "runner did not archive the results table"

expect_failure 2 "unknown preset: surprise" \
  env "${runner_env[@]}" "$runner" --preset surprise "$upstream"
expect_failure 2 "--benchmark requires a workload ID or prefix" \
  env "${runner_env[@]}" "$runner" --benchmark
expect_failure 2 "invalid framework name: keyed/bad/name" \
  env "${runner_env[@]}" "$runner" --framework keyed/bad/name --smoke "$upstream"
expect_failure 2 "framework not found in pinned upstream release: keyed/missing" \
  env "${runner_env[@]}" "$runner" --framework keyed/missing --smoke "$upstream"

prepare_harness="$workspace/prepare-harness"
prepare_fake_bin="$prepare_harness/fake-bin"
prepare_real_shasum_bin="$prepare_harness/fake-bin-real-shasum"
prepare_log="$prepare_harness/calls.log"
mkdir -p "$prepare_harness/scripts"
cp "$repository_root/scripts/prepare_js_framework_benchmark.sh" "$prepare_harness/scripts/"
chmod +x "$prepare_harness/scripts/prepare_js_framework_benchmark.sh"
make_fake_bin "$prepare_fake_bin" npm curl git lake shasum unzip
make_fake_bin "$prepare_real_shasum_bin" npm curl git lake unzip
: >"$prepare_log"

prepare="$prepare_harness/scripts/prepare_js_framework_benchmark.sh"
prepare_env=(
  "PATH=$prepare_fake_bin:$PATH"
  "LEANRX_BENCH_TEST_LOG=$prepare_log"
)

make_checkout() {
  local directory="$1"
  mkdir -p "$directory/.git"
  printf '%s\n' '{"name": "js-framework-benchmark"}' >"$directory/package.json"
}

wrong_commit="$prepare_harness/wrong-commit"
make_checkout "$wrong_commit"
expect_failure 1 "actual commit: deadbeef" \
  env "${prepare_env[@]}" LEANRX_FAKE_GIT_HEAD=deadbeef "$prepare" "$wrong_commit"

bad_archive="$prepare_harness/bad-archive"
make_checkout "$bad_archive"
: >"$bad_archive/build.zip"
expect_failure 1 "build.zip checksum mismatch" \
  env "PATH=$prepare_real_shasum_bin:$PATH" "LEANRX_BENCH_TEST_LOG=$prepare_log" \
  "$prepare" --prebuilt "$bad_archive"

prepared="$prepare_harness/prepared"
make_checkout "$prepared"
: >"$prepared/build.zip"
: >"$prepare_log"
if ! prepare_output="$(env "${prepare_env[@]}" "$prepare" --prebuilt --install "$prepared" 2>&1)"; then
  fail "prepare unexpectedly failed: $prepare_output"
fi
prepare_calls="$(<"$prepare_log")"
assert_contains "$prepare_calls" "unzip|-q -o $prepared/build.zip -d $prepared"
assert_contains "$prepare_calls" "npm|ci"
assert_contains "$prepare_calls" "npm|run install-local"
[[ -f "$prepared/.leanrx-prebuilt-fa15a77d73dca6dfc0a97ce8c4d6c0797726fa75" ]] ||
  fail "prepare did not create the prebuilt marker"
[[ -f "$prepared/frameworks/keyed/leanrx/package.json" ]] ||
  fail "prepare did not publish the LeanRx framework"

: >"$prepare_log"
if ! prepare_output="$(env "${prepare_env[@]}" "$prepare" --prebuilt "$prepared" 2>&1)"; then
  fail "repeat prepare unexpectedly failed: $prepare_output"
fi
assert_contains "$prepare_output" "existing pinned pre-built frameworks are ready"
assert_not_contains "$(<"$prepare_log")" "unzip|"

foreign_target="$prepare_harness/foreign-target"
make_checkout "$foreign_target"
mkdir -p "$foreign_target/frameworks/keyed/leanrx"
printf '%s\n' '{"name": "not-leanrx"}' >"$foreign_target/frameworks/keyed/leanrx/package.json"
expect_failure 1 "refusing to replace an unrecognized framework directory" \
  env "${prepare_env[@]}" "$prepare" "$foreign_target"

expect_failure 2 "unknown option: --surprise" \
  "$repository_root/scripts/prepare_js_framework_benchmark.sh" --surprise
expect_failure 2 "only one upstream directory may be supplied" \
  "$repository_root/scripts/prepare_js_framework_benchmark.sh" one two

echo "JS framework benchmark script tests passed"
