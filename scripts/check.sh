#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/check.sh

Validate the repository without installing anything:
  - evaluate the anix and both amac system derivations
  - run bash -n on every file in scripts/
  - run shellcheck on every scripts/ file from PATH or nixpkgs
  - run typos over the repository when typos is on PATH

Options:
  -h, --help  Show this help and exit.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir/.." rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  repo_root="$(cd "$script_dir/.." && pwd)"
fi

fail() {
  echo "check: $*" >&2
  exit 1
}

if ! command -v nix >/dev/null 2>&1; then
  fail "nix not found on PATH"
fi

cd "$repo_root"

nix_flags=(--extra-experimental-features "nix-command flakes")

echo "==> nix eval .#nixosConfigurations.anix"
nix "${nix_flags[@]}" eval --raw ".#nixosConfigurations.anix.config.system.build.toplevel.drvPath" >/dev/null ||
  fail "anix configuration eval failed"

for config in amac amac-intel; do
  echo "==> nix eval .#darwinConfigurations.$config"
  nix "${nix_flags[@]}" eval --raw ".#darwinConfigurations.$config.config.system.build.toplevel.drvPath" >/dev/null ||
    fail "$config configuration eval failed"
done

echo "==> bash -n scripts/*"
while IFS= read -r -d '' file; do
  bash -n "$file" || fail "syntax error in ${file#"$repo_root"/}"
done < <(find "$repo_root/scripts" -maxdepth 1 -type f ! -name '*.ps1' -print0)

echo "==> shellcheck scripts/*"
while IFS= read -r -d '' file; do
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$file" || fail "shellcheck failed for ${file#"$repo_root"/}"
  else
    nix "${nix_flags[@]}" shell --inputs-from "$repo_root" nixpkgs#shellcheck -c shellcheck "$file" ||
      fail "shellcheck failed for ${file#"$repo_root"/}"
  fi
done < <(find "$repo_root/scripts" -maxdepth 1 -type f ! -name '*.ps1' -print0)

echo "==> typos"
if command -v typos >/dev/null 2>&1; then
  typos --force-exclude || fail "typos found spelling errors"
else
  nix "${nix_flags[@]}" shell --inputs-from "$repo_root" nixpkgs#typos -c typos --force-exclude ||
    fail "typos found spelling errors"
fi

echo "check: ok"
