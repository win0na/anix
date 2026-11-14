{
  lib,
  pkgs,
  hostSystem,
  # The Intel Mac installs MacPorts as root; the parameter stays in the
  # signature because it comes from the shared amac specialArgs and the pkg
  # postinstall must never rewrite this user's dotfiles.
  userName,
  ...
}:

let
  isIntel = hostSystem == "x86_64-darwin";

  prefix = "/opt/local";
  pkgVersion = "2.12.7";
  # The 26-Tahoe pkg is universal and the only build that runs on macOS 26.
  pkg = pkgs.fetchurl {
    url = "https://github.com/macports/macports-base/releases/download/v${pkgVersion}/MacPorts-${pkgVersion}-26-Tahoe.pkg";
    hash = "sha256-WI8UzNPGGZVZoHCoDmzd1ocXIaCMxDR3W/VDeP1meRA=";
  };
in
{
  # MacPorts first: its own docs and ports expect /opt/local/bin ahead of the
  # system prefix, and the Intel host installs there.
  environment.systemPath = lib.mkIf isIntel (lib.mkBefore [
    "${prefix}/bin"
    "${prefix}/sbin"
  ]);

  # Activation runs as root with a minimal PATH. postActivation is one of the
  # few keys nix-darwin dispatches, and mkBefore keeps this before the sops
  # autologin block (1500/1600) and before Home Manager's own text.
  system.activationScripts.postActivation.text = lib.mkIf isIntel (lib.mkBefore ''
    # The pkg installer writes /opt/local as root and its postinstall runs
    # `port -v selfupdate` in root's shell; nothing here touches
    # /Users/${userName}.
    macports_prefix=${prefix}

    macports_have=$(
      "$macports_prefix/bin/port" version 2>/dev/null | /usr/bin/awk '{ print $2 }' || true
    )
    # Install when the release is missing or older. A newer release than the
    # pin is left alone; the sentinel is trusted only together with a working
    # port binary at the pinned version, so a stale file cannot suppress the
    # install.
    macports_install=0
    if [ ! -x "$macports_prefix/bin/port" ] || [ "$macports_have" != "${pkgVersion}" ]; then
      if [ -z "$macports_have" ]; then
        macports_install=1
      elif [ ! -e "$macports_prefix/.anix-pkg-${pkgVersion}-588f14cc" ] && \
        [ "$(/usr/bin/printf '%s\n%s\n' "$macports_have" "${pkgVersion}" | /usr/bin/sort -V | /usr/bin/head -n 1)" = "$macports_have" ]; then
        macports_install=1
      fi
    fi
    if [ "$macports_install" = 1 ]; then
      if /usr/sbin/installer -pkg ${pkg} -target / && [ -x "$macports_prefix/bin/port" ]; then
        /usr/bin/touch "$macports_prefix/.anix-pkg-${pkgVersion}-588f14cc"
      else
        echo "macports: pkg install failed; rerun: sudo installer -pkg ${pkg} -target /" >&2
      fi
    fi

    if [ -x "$macports_prefix/bin/port" ]; then
      # Refresh the port index only. selfupdate rebuilds MacPorts itself and
      # can take minutes, so a stale index wins over a failed switch.
      ${lib.getExe' pkgs.coreutils "timeout"} -k 10 300 "$macports_prefix/bin/port" sync ||
        macports_sync_status=$?
      if [ "''${macports_sync_status:-0}" -ne 0 ]; then
        if [ "''${macports_sync_status:-0}" -eq 124 ]; then
          /usr/bin/find "$macports_prefix/var/macports/sources" -maxdepth 2 -name '*.lock' \
            -delete 2>/dev/null || true
          echo "macports: port sync timed out; cleared stale locks, rerun: sudo port sync" >&2
        else
          echo "macports: port sync failed; run: sudo port sync" >&2
        fi
      fi
    fi

    # The shim serves brew's layout out of the MacPorts prefix. Each installed
    # port gets <prefix>/Cellar/<name>/<version> holding links to the prefix's
    # trees, and <prefix>/opt/<name> pointing at it. The tree is never a link
    # to the prefix itself, so a recursive walk of one formula cannot reach
    # every port.
    macports_layout_ok=1
    if ! /bin/mkdir -p "$macports_prefix/Cellar" "$macports_prefix/opt" 2>/dev/null; then
      echo "macports: cannot create Cellar/opt under $macports_prefix; skipping the brew layout" >&2
      macports_layout_ok=0
    fi
    if [ "$macports_layout_ok" = 1 ] && macports_installed=$("$macports_prefix/bin/port" -q installed 2>/dev/null); then
      macports_map=$(/usr/bin/mktemp /tmp/anix-macports.XXXXXX)
      printf '%s\n' "$macports_installed" | /usr/bin/awk '
        $2 ~ /^@/ {
          name = $1
          version = $2
          sub(/^@/, "", version)
          sub(/\+.*$/, "", version)
          sub(/_[0-9]+$/, "", version)
          if (name != "" && version != "") print name, version
        }
      ' > "$macports_map"
      while read -r macports_name macports_version; do
        case "$macports_name" in ""|.|..|*/*) continue ;; esac
        case "$macports_version" in ""|.|..|*/*) continue ;; esac
        macports_cellar="$macports_prefix/Cellar/$macports_name"
        [ -L "$macports_cellar" ] && continue
        /bin/mkdir -p "$macports_cellar" || { macports_layout_ok=0; continue; }
        macports_version_dir="$macports_cellar/$macports_version"
        [ -L "$macports_version_dir" ] && continue
        /bin/mkdir -p "$macports_version_dir" || { macports_layout_ok=0; continue; }
        for macports_sub in bin sbin lib include share etc libexec; do
          [ -e "$macports_prefix/$macports_sub" ] &&
            { /bin/ln -sfn "$macports_prefix/$macports_sub" "$macports_version_dir/$macports_sub" ||
              macports_layout_ok=0; }
        done
        /bin/ln -sfn "$macports_version_dir" "$macports_prefix/opt/$macports_name" ||
          macports_layout_ok=0
      done < "$macports_map"
      # Drop links for ports or versions that are no longer installed.
      for macports_link in "$macports_prefix"/opt/*; do
        [ -L "$macports_link" ] || continue
        macports_name=''${macports_link##*/}
        /usr/bin/awk -v n="$macports_name" '$1 == n { found = 1 } END { exit !found }' "$macports_map" ||
          /bin/rm -f -- "$macports_link"
      done
      for macports_cellar in "$macports_prefix"/Cellar/*; do
        [ -d "$macports_cellar" ] && [ ! -L "$macports_cellar" ] || continue
        macports_name=''${macports_cellar##*/}
        for macports_version_dir in "$macports_cellar"/*; do
          [ -d "$macports_version_dir" ] && [ ! -L "$macports_version_dir" ] || continue
          macports_version=''${macports_version_dir##*/}
          if ! /usr/bin/awk -v n="$macports_name" -v v="$macports_version" \
            '$1 == n && $2 == v { found = 1 } END { exit !found }' "$macports_map"; then
            /bin/rm -rf -- "$macports_version_dir"
            continue
          fi
          for macports_link in "$macports_version_dir"/*; do
            [ -L "$macports_link" ] || continue
            [ -e "$macports_link" ] || /bin/rm -f -- "$macports_link"
          done
        done
        /bin/rmdir "$macports_cellar" 2>/dev/null || true
      done
      /bin/rm -f -- "$macports_map"
      if [ "$macports_layout_ok" = 0 ]; then
        echo "macports: brew layout incomplete; rerun the switch" >&2
      fi
    elif [ "$macports_layout_ok" = 1 ]; then
      echo "macports: port -q installed failed; leaving the brew layout alone" >&2
    fi
  '');
}
