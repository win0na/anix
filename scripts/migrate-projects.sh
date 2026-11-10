#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/migrate-projects.sh [--dry-run] [name...]

Move project directories from HOME into HOME/src and leave a relative symlink
at the old path. Run on Linux or WSL.

With no names, the script prints candidate directories (immediate children of
HOME that contain .git) and exits 1.

Options:
  -h, --help  Show this help and exit.
  --dry-run   Print the mkdir, mv, and ln commands without changing anything.
EOF
}

dry_run=0
names=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --)
      shift
      names+=("$@")
      break
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      names+=("$1")
      shift
      ;;
  esac
done

run() {
  if [[ $dry_run -eq 1 ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    printf '==>'
    printf ' %q' "$@"
    printf '\n'
    "$@"
  fi
}

if [[ ${#names[@]} -eq 0 ]]; then
  echo "Candidate project directories in $HOME (contain .git):"
  found=0
  for dir in "$HOME"/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    [[ "$name" == "src" ]] && continue
    [[ -e "$dir/.git" ]] || continue
    printf '  %s\n' "$name"
    found=1
  done
  if [[ $found -eq 0 ]]; then
    echo "  (none)"
  fi
  echo "Rerun with one or more names: scripts/migrate-projects.sh name..." >&2
  exit 1
fi

if [[ $dry_run -eq 1 ]]; then
  printf '[dry-run] mkdir -p %q\n' "$HOME/src"
else
  mkdir -p "$HOME/src"
fi

for name in "${names[@]}"; do
  if [[ -z "$name" || "$name" == */* || "$name" == "." || "$name" == ".." ]]; then
    echo "warning: skipping invalid name: $name" >&2
    continue
  fi

  if [[ "$name" == "anix" ]]; then
    echo "error: refusing to migrate anix; the repo must stay where it is while this script runs" >&2
    exit 1
  fi

  old="$HOME/$name"
  new="$HOME/src/$name"

  if [[ -L "$old" ]]; then
    echo "skip: $old is already a symlink"
    continue
  fi

  if [[ -e "$new" && ! -e "$old" ]]; then
    run ln -s "src/$name" "$old"
  elif [[ -e "$old" && ! -e "$new" ]]; then
    run mv "$old" "$new"
    run ln -s "src/$name" "$old"
  elif [[ -e "$old" && -e "$new" ]]; then
    echo "warning: both $old and $new exist; skipping" >&2
  else
    echo "warning: neither $old nor $new exists" >&2
  fi
done
