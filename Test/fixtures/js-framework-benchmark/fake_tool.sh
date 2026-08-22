#!/usr/bin/env bash
set -euo pipefail

tool="${0##*/}"
log="${LEANRX_BENCH_TEST_LOG:?LEANRX_BENCH_TEST_LOG is required}"

record() {
  printf '%s|%s\n' "$tool" "$*" >>"$log"
}

case "$tool" in
  npm)
    record "$@"
    if [[ "${1:-}" == "start" ]]; then
      trap 'exit 0' TERM INT
      while true; do
        /bin/sleep 1
      done
    fi
    if [[ "${1:-}" == "run" && "${2:-}" == "bench" ]]; then
      mkdir -p "$PWD/webdriver-ts/results"
      printf '%s\n' '{"fixture":true}' >"$PWD/webdriver-ts/results/fixture.json"
    fi
    if [[ "${1:-}" == "run" && "${2:-}" == "results" ]]; then
      mkdir -p "$PWD/webdriver-ts-results/dist"
      printf '%s\n' '<!doctype html>' >"$PWD/webdriver-ts-results/dist/index.html"
    fi
    if [[ "${1:-}" == "--version" ]]; then
      echo "10.0.0-fixture"
    fi
    ;;
  curl)
    record "$@"
    ;;
  git)
    record "$@"
    if [[ " $* " == *" rev-parse HEAD "* ]]; then
      echo "${LEANRX_FAKE_GIT_HEAD:-fa15a77d73dca6dfc0a97ce8c4d6c0797726fa75}"
    fi
    ;;
  lake)
    record "$@"
    if [[ "${1:-}" == "--version" ]]; then
      echo "Lake fixture"
      exit 0
    fi
    output=""
    while (( $# > 0 )); do
      if [[ "$1" == "--" && $# -ge 2 ]]; then
        output="$2"
        break
      fi
      shift
    done
    if [[ -n "$output" ]]; then
      mkdir -p "$output"
      printf '%s\n' '{"name": "js-framework-benchmark-leanrx"}' >"$output/package.json"
      printf '%s\n' 'fixture' >"$output/LeanRx.mjs"
    fi
    ;;
  shasum)
    record "$@"
    printf '%s  %s\n' \
      '1bff881fb7d23210e5bc4e886373da1002c88c912f0cd165e60921e8c10b38e0' \
      "${*: -1}"
    ;;
  unzip)
    record "$@"
    destination=""
    while (( $# > 0 )); do
      if [[ "$1" == "-d" && $# -ge 2 ]]; then
        destination="$2"
        break
      fi
      shift
    done
    if [[ -n "$destination" ]]; then
      mkdir -p "$destination"
    fi
    ;;
  *)
    echo "unknown fixture tool: $tool" >&2
    exit 1
    ;;
esac
