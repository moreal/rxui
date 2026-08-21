#!/usr/bin/env bash
set -euo pipefail

upstream_url="https://github.com/krausest/js-framework-benchmark.git"
upstream_tag="chrome150"
upstream_commit="fa15a77d73dca6dfc0a97ce8c4d6c0797726fa75"
install_dependencies=false
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
upstream_directory="$repository_root/.tmp/js-framework-benchmark"

while (( $# > 0 )); do
  case "$1" in
    --install)
      install_dependencies=true
      shift
      ;;
    --help|-h)
      echo "usage: $0 [--install] [upstream-directory]"
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

if [[ ! -e "$upstream_directory" ]]; then
  mkdir -p "$(dirname "$upstream_directory")"
  git clone --depth 1 --branch "$upstream_tag" "$upstream_url" "$upstream_directory"
fi

if [[ ! -d "$upstream_directory/.git" ]] ||
    [[ ! -f "$upstream_directory/package.json" ]] ||
    ! grep -Fq '"name": "js-framework-benchmark"' "$upstream_directory/package.json"; then
  echo "not a js-framework-benchmark checkout: $upstream_directory" >&2
  exit 1
fi

actual_commit="$(git -C "$upstream_directory" rev-parse HEAD)"
if [[ "$actual_commit" != "$upstream_commit" ]]; then
  echo "upstream checkout must be pinned to $upstream_tag ($upstream_commit)" >&2
  echo "actual commit: $actual_commit" >&2
  exit 1
fi

workspace="$(mktemp -d)"
output="$workspace/dist"
frameworks_directory="$upstream_directory/frameworks/keyed"
target="$frameworks_directory/leanrx"
staging="$frameworks_directory/.leanrx-staging-$$"
trap 'rm -rf -- "$workspace" "$staging"' EXIT

cd "$repository_root"
lake exe leanrx_js_framework_benchmark -- "$output"
mkdir -p "$staging"
cp -R "$output/." "$staging/"

if [[ -e "$target" ]]; then
  if [[ ! -f "$target/package.json" ]] ||
      ! grep -Fq '"name": "js-framework-benchmark-leanrx"' "$target/package.json"; then
    echo "refusing to replace an unrecognized framework directory: $target" >&2
    exit 1
  fi
  rm -rf -- "$target"
fi
mv "$staging" "$target"

if [[ "$install_dependencies" == true ]]; then
  (
    cd "$upstream_directory"
    npm ci
    npm run install-local
  )
fi

echo "prepared keyed/leanrx at $target"
echo "upstream $upstream_tag commit $upstream_commit"
if [[ "$install_dependencies" == false ]]; then
  if [[ -d "$upstream_directory/node_modules" ]] &&
      [[ -f "$upstream_directory/webdriver-ts/dist/benchmarkRunner.js" ]] &&
      [[ -d "$upstream_directory/server/node_modules" ]]; then
    echo "existing upstream dependencies are ready"
  else
    echo "dependencies were not installed; rerun with --install before the first full benchmark"
  fi
fi
