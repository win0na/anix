#!/usr/bin/env bats

setup() {
  load lib
  e2e_setup
}

teardown() {
  cd /
}

@test "provision installs anix and prepares the Mac" {
  run "$fx/repo/scripts/provision" --yes
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }

  assert_nonempty "$fx/win/Users/e2e/anix-ubuntu-backup.tar.age"

  local nixos
  nixos=$(e2e_distro_home NixOS)
  assert_nonempty "$nixos/.config/anix/flake.nix"
  grep -qx 'personal' <(git -C "$nixos/.config/anix" branch --show-current)
  grep -q '^  anix: &anix age1' "$nixos/.config/anix/.sops.yaml"
  grep -q '^  amac: &amac age1' "$nixos/.config/anix/.sops.yaml"

  assert_mode "$nixos/.config/sops/age/keys.txt" 600
  assert_mode "$nixos/.ssh/mac-builder" 600

  assert_file "$fx/system/switch.ok"
  assert_nonempty "$fx/mac/.config/anix/flake.nix"
  assert_file "$fx/mac/anix-first-switch/first-switch.command"
  [[ -x $fx/mac/anix-first-switch/first-switch.command ]]

  [[ -d $fx/wsl/distros/Ubuntu ]]
  [[ ! -e $fx/wsl/distros/NixOS/.config ]]
}

@test "provision refuses to install the distribution it runs in" {
  run env WSL_DISTRO_NAME=NixOS "$fx/repo/scripts/provision" --yes
  [ "$status" -ne 0 ]
  assert_contains "$output" "refusing to run against NixOS"
}

@test "a missing nfsd stops the Mac phase and keeps Ubuntu" {
  run env ANIX_E2E_NFSD=0 "$fx/repo/scripts/provision" --yes --no-transfer --skip-backup
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_contains "$output" "needs the NFS export"
  [[ ! -e $fx/mac/.config/anix ]]
  [[ -d $fx/wsl/distros/Ubuntu ]]
}

@test "a failed Ubuntu export stops before the install" {
  run env ANIX_E2E_EXPORT=fail "$fx/repo/scripts/provision" --yes --no-mac
  [ "$status" -ne 0 ]
  assert_contains "$output" "backup cancelled"
  [[ ! -e $fx/wsl/distros/NixOS ]]
}

@test "skip-backup installs without an archive and keeps Ubuntu" {
  run "$fx/repo/scripts/provision" --yes --no-mac --skip-backup
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ ! -e $fx/win/Users/e2e/anix-ubuntu-backup.tar.age ]]
  [[ -d $fx/wsl/distros/Ubuntu ]]
}

@test "a second run skips the first switch and keeps the checkout" {
  run "$fx/repo/scripts/provision" --yes --no-mac --skip-backup
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }

  local nixos
  nixos=$(e2e_distro_home NixOS)
  printf 'keep\n' >"$nixos/.config/anix/local-marker"

  run "$fx/repo/scripts/provision" --yes --no-mac --skip-backup
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_contains "$output" "already has"
  assert_file "$nixos/.config/anix/local-marker"
}

@test "bootstrap-mac-remote dry-run reads the checkout and keys" {
  run "$fx/repo/scripts/bootstrap-mac-remote" --dry-run --yes
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_contains "$output" "Dry run: Mac host amac, user"
}

@test "bootstrap prepare generates keys on a fresh home" {
  rm -rf "$HOME/.config/sops/age" "$HOME/.ssh"
  rm -f "$fx/repo/secrets/secrets.yaml"

  run "$fx/repo/scripts/bootstrap" --prepare --yes --no-install
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }

  assert_mode "$HOME/.config/sops/age/keys.txt" 600
  assert_mode "$HOME/.ssh/mac-builder" 600
  assert_nonempty "$fx/repo/secrets/secrets.yaml"
  grep -q '^  personal: &personal ' "$fx/repo/.sops.yaml"
}
