#!/usr/bin/env bash

# Read the tracked project settings from users.nix. Source this after setting
# repo_root, or pass the users.nix path as the last argument.

anix_value_from_users() {
  local key=$1 file=${2:-${repo_root:-}/users.nix}
  [[ -n $file ]] || return 1
  sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$file" | head -1
}

anix_projects_dir() {
  local file=${1:-${repo_root:-}/users.nix} value
  value=$(anix_value_from_users projectsDir "$file")
  printf '%s\n' "${value:-src}"
}

anix_projects_path() {
  local home=$1 dir=$2
  case "$dir" in
    /*) printf '%s\n' "$dir" ;;
    *) printf '%s/%s\n' "$home" "$dir" ;;
  esac
}

anix_projects_name() {
  local path=$1
  printf '%s\n' "${path##*/}"
}
