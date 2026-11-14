#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/check.sh

Validate the repository without installing anything:
  - evaluate the anix and both amac system derivations
  - run bash -n on every file in scripts/
  - run shellcheck on every scripts/ file from PATH or nixpkgs
  - parse scripts/bootstrap-windows.ps1 with pwsh
  - run the brew-shim Rust tests
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

echo "==> pwsh parse scripts/bootstrap-windows.ps1"
if command -v pwsh >/dev/null 2>&1; then
  pwsh_bin=pwsh
else
  pwsh_bin=""
fi
if [[ -n $pwsh_bin ]]; then
  "$pwsh_bin" -NoProfile -Command '$e = $null; $t = $null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "scripts/bootstrap-windows.ps1"), [ref]$t, [ref]$e) | Out-Null; if ($e) { $e | ForEach-Object { Write-Error $_ }; exit 1 }' ||
    fail "PowerShell parse failed for scripts/bootstrap-windows.ps1"
else
  nix "${nix_flags[@]}" shell --inputs-from "$repo_root" nixpkgs#powershell -c pwsh -NoProfile -Command '$e = $null; $t = $null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "scripts/bootstrap-windows.ps1"), [ref]$t, [ref]$e) | Out-Null; if ($e) { $e | ForEach-Object { Write-Error $_ }; exit 1 }' ||
    fail "PowerShell parse failed for scripts/bootstrap-windows.ps1"
fi

echo "==> cargo test pkgs/brew-shim"
if command -v cargo >/dev/null 2>&1; then
  cargo test --quiet --manifest-path "$repo_root/pkgs/brew-shim/Cargo.toml" ||
    fail "brew-shim tests failed"
else
  nix "${nix_flags[@]}" shell --inputs-from "$repo_root" nixpkgs#cargo nixpkgs#rustc -c \
    cargo test --quiet --manifest-path "$repo_root/pkgs/brew-shim/Cargo.toml" ||
    fail "brew-shim tests failed"
fi

echo "==> typos"
if command -v typos >/dev/null 2>&1; then
  typos --force-exclude --exclude 'pkgs/*/target' || fail "typos found spelling errors"
else
  nix "${nix_flags[@]}" shell --inputs-from "$repo_root" nixpkgs#typos -c typos --force-exclude --exclude 'pkgs/*/target' ||
    fail "typos found spelling errors"
fi

echo "check: ok"
