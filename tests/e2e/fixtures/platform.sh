#!/usr/bin/env bash
# Platform module for the install E2E. The case runs on the test host, so the
# host checks are answered for it and the system paths point at the case dir.
anix_find_nix() { command -v nix >/dev/null 2>&1; }

anix_is_nixos() { true; }

anix_proc_version() {
  printf 'Linux version 6.6.87.2-microsoft-standard-WSL2 (gcc version 13.2.0)\n'
}

anix_is_wsl2() { true; }

anix_in_wsl() { true; }

anix_anix_host_key() {
  printf '%s/etc/ssh/ssh_host_ed25519_key\n' "${ANIX_E2E_SYSTEM:?}"
}

anix_builder_key_install() {
  printf '%s/etc/nix/mac-builder\n' "${ANIX_E2E_SYSTEM:?}"
}
