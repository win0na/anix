#!/usr/bin/env bats

setup() {
  load lib
  source "$ANIX_E2E_SOURCE/scripts/lib/config.sh"
  users=$BATS_TEST_TMPDIR/users.nix
}

write_users() {
  cat >"$users"
}

@test "users.nix values are read with comments stripped" {
  write_users <<'NIX'
{
  # anix = "commented";
  anix = "winona";
  amac = "macuser"; # inline
  projectsDir = "src";
}
NIX
  [ "$(anix_value_from_users anix "$users")" = winona ]
  [ "$(anix_value_from_users amac "$users")" = macuser ]
}

@test "a one-line users.nix is read" {
  printf '{ anix = "a"; amac = "b"; projectsDir = "code"; }\n' >"$users"
  [ "$(anix_value_from_users projectsDir "$users")" = code ]
  [ "$(anix_projects_dir "$users")" = code ]
}

@test "projectsDir defaults to src" {
  printf '{ anix = "a"; amac = "b"; }\n' >"$users"
  [ "$(anix_projects_dir "$users")" = src ]
  [ "$(anix_projects_dir /nonexistent)" = src ]
}

@test "project roots reject hidden segments and Windows mounts" {
  anix_check_projects_dir src /home/u
  anix_check_projects_dir /home/u/src /home/u
  anix_check_projects_dir /mnt/data/src /home/u
  run anix_check_projects_dir .config /home/u
  [ "$status" -ne 0 ]
  run anix_check_projects_dir /mnt/c/src /home/u
  [ "$status" -ne 0 ]
  run anix_check_projects_dir /home/u /home/u
  [ "$status" -ne 0 ]
  run anix_check_projects_dir /etc/src /home/u
  [ "$status" -ne 0 ]
}

@test "projects path joins relative roots under the home" {
  [ "$(anix_projects_path /home/u src)" = /home/u/src ]
  [ "$(anix_projects_path /home/u /mnt/data/src)" = /mnt/data/src ]
}
