#!/usr/bin/env bash
# Resolve the test tools, then run the install E2E with bats.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export ANIX_E2E_SOURCE=$root

nix_flags=(--extra-experimental-features 'nix-command flakes')
mapfile -t store < <(nix "${nix_flags[@]}" build --no-link --print-out-paths \
  --inputs-from "$root" nixpkgs#bats nixpkgs#sops nixpkgs#age nixpkgs#ssh-to-age)

bin=
for path in "${store[@]}"; do
  bin="${bin:+$bin:}$path/bin"
done
export ANIX_E2E_BIN=$bin
export PATH="$ANIX_E2E_BIN:$PATH"

if (($#)); then
  exec bats "$@"
fi
exec bats "$root/tests/e2e"
