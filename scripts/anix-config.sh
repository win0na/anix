#!/usr/bin/env bash

# Read the tracked project settings from users.nix. Source this after setting
# repo_root, or pass the users.nix path as the last argument.

anix_value_from_users() {
  local key=$1 file=${2:-${repo_root:-}/users.nix}
  [[ -n $file && -s $file ]] || return 1
  # Strip comments and flatten first: a commented-out assignment or a
  # hand-written one-line users.nix must not change the answer.
  sed 's/#.*//' "$file" |
    tr '\n\r' '  ' |
    grep -oE "(^|[^A-Za-z0-9_])${key}[[:space:]]*=[[:space:]]*\"[^\"]*\"" |
    head -1 |
    sed 's/^[^"]*"//; s/"$//' || true
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

anix_check_projects_dir() {
  local dir=$1 home=${2:-} segment lower
  local -a parts=()
  [[ -n $dir && $dir != "/" ]] || return 1
  # The flake strips one trailing slash; do the same so both agree on `src/`.
  dir=${dir%/}
  [[ -n $dir && $dir != "/" ]] || return 1
  [[ $dir =~ ^[A-Za-z0-9._/-]+$ ]] || return 1
  [[ $dir == *//* ]] && return 1
  IFS=/ read -r -a parts <<< "$dir"
  for segment in "${parts[@]}"; do
    # The leading slash of an absolute path yields one empty segment.
    [[ -n $segment ]] || continue
    # A hidden directory can hold keys or a tunnel token.
    [[ $segment == .* ]] && return 1
    lower=$(printf '%s' "$segment" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
      applications|desktop|documents|downloads|library|movies|music|pictures|public|system|users) return 1 ;;
    esac
  done
  case "$dir" in
    /*)
      # Only the anix home and a non-WSL /mnt path may be exported.
      if [[ -n $home && $dir == "$home"/* ]]; then
        :
      else
        [[ $dir == /mnt/* ]] || return 1
        [[ $dir == /mnt/[A-Za-z] || $dir == /mnt/[A-Za-z]/* ]] && return 1
        [[ $dir == /mnt/wsl || $dir == /mnt/wsl/* ]] && return 1
        [[ $dir == /mnt/wslg || $dir == /mnt/wslg/* ]] && return 1
      fi
      ;;
  esac
  [[ -n $home && $dir == "$home" ]] && return 1
  return 0
}
