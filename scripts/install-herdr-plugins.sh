#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/install-herdr-plugins.sh

Link the first-party responsive-sidebar plugin and list installed plugins.

The herdr-bar, herdr-sidebar, and ttt.editor plugins are installed
declaratively by Home Manager. This script prints their pinned commits and
does not install them.

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

if ! command -v herdr >/dev/null 2>&1; then
  echo "error: herdr not found on PATH" >&2
  exit 1
fi

plugin="$repo_root/pkgs/herdr-plugins/responsive-sidebar"
if [[ ! -d "$plugin" ]]; then
  echo "error: plugin directory not found: $plugin" >&2
  exit 1
fi

# link registers the plugin enabled; there is no --enabled flag.
echo "==> herdr plugin link $plugin"
herdr plugin link "$plugin"

cat <<'EOF'

Installed declaratively by Home Manager (pinned commits):
  herdr-bar      d9cdd88cb734615e96b1c37ed17fc39be904f060
  herdr-sidebar  081ed133f3faa377438b51ce435fe8a87c439593
  ttt.editor     b51ae983e0f60599090e0b0061093dbece9b541f

Run scripts/rebuild to apply the Home Manager set, or install these from the
Herdr plugin registry.
EOF

echo "==> herdr plugin list"
herdr plugin list
