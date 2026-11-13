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

anix_check_projects_dir() {
  local dir=$1 home=${2:-} segment name
  local -a parts=()
  [[ -n $dir && $dir != "/" ]] || return 1
  # The flake strips one trailing slash; do the same so both agree on `src/`.
  dir=${dir%/}
  [[ -n $dir && $dir != "/" ]] || return 1
  [[ $dir =~ ^[A-Za-z0-9._/-]+$ ]] || return 1
  [[ $dir == *//* ]] && return 1
  IFS=/ read -r -a parts <<< "$dir"
  for segment in "${parts[@]}"; do
    [[ $segment == "." || $segment == ".." ]] && return 1
  done
  case "$dir" in
    /*)
      [[ $dir == /home/* || $dir == /mnt/* ]] || return 1
      [[ $dir == /mnt/[A-Za-z] || $dir == /mnt/[A-Za-z]/* ]] && return 1
      ;;
  esac
  [[ -n $home && $dir == "$home" ]] && return 1
  name=${dir##*/}
  name=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
  case "$name" in
    applications|desktop|documents|downloads|library|movies|music|pictures|public|system|users|.config|.ssh) return 1 ;;
  esac
  return 0
}
