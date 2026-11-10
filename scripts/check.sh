#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/check.sh

Validate the repository without installing anything:
  - evaluate the anix and amac system derivations
  - run bash -n on every file in scripts/
  - run shellcheck on every scripts/ file when shellcheck is on PATH

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

echo "==> nix eval .#darwinConfigurations.amac"
nix "${nix_flags[@]}" eval --raw ".#darwinConfigurations.amac.config.system.build.toplevel.drvPath" >/dev/null ||
  fail "amac configuration eval failed"

echo "==> bash -n scripts/*"
while IFS= read -r -d '' file; do
  bash -n "$file" || fail "syntax error in ${file#"$repo_root"/}"
done < <(find "$repo_root/scripts" -maxdepth 1 -type f -print0)

if command -v shellcheck >/dev/null 2>&1; then
  echo "==> shellcheck scripts/*"
  while IFS= read -r -d '' file; do
    shellcheck "$file" || fail "shellcheck failed for ${file#"$repo_root"/}"
  done < <(find "$repo_root/scripts" -maxdepth 1 -type f -print0)
else
  echo "check: shellcheck not found; skipping"
fi

echo "check: ok"
