#!/usr/bin/env bash

# Host detection and tool discovery shared by the anix scripts.

# Put a Nix installation on PATH when the login shell has not done it.
anix_find_nix() {
  command -v nix >/dev/null 2>&1 && return 0
  local dir
  for dir in "$HOME/.nix-profile/bin" /nix/var/nix/profiles/default/bin; do
    if [[ -x "$dir/nix" ]]; then
      PATH="$dir:$PATH"
      export PATH
      return 0
    fi
  done
  return 1
}

anix_is_nixos() { [[ -e /etc/NIXOS ]]; }

anix_proc_version() { cat /proc/version 2>/dev/null || true; }

# WSL2, not WSL1. The kernel string is the only reliable marker once
# /etc/wsl.conf changes the distribution name.
anix_is_wsl2() {
  local version
  version=$(anix_proc_version)
  [[ -n $version ]] && grep -qi 'microsoft-standard-WSL2' <<<"$version"
}

anix_in_wsl() { [[ -n ${WSL_DISTRO_NAME:-} ]]; }

# Absolute paths the anix host writes. A test platform module can point these
# at a scratch directory; the production module keeps the system paths.
anix_anix_host_key() { printf '/etc/ssh/ssh_host_ed25519_key\n'; }

anix_builder_key_install() { printf '/etc/nix/mac-builder\n'; }
