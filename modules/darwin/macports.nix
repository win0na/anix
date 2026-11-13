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
    # Install only when the release is missing or older. A newer release than
    # the pin, or a sentinel from an earlier install, is left alone so a switch
    # cannot downgrade the base behind the operator's back.
    macports_install=0
    if [ ! -e "$macports_prefix/.anix-pkg-588f14cc" ]; then
      if [ -z "$macports_have" ]; then
        macports_install=1
      elif [ "$macports_have" != "${pkgVersion}" ] && \
        [ "$(/usr/bin/printf '%s\n%s\n' "$macports_have" "${pkgVersion}" | /usr/bin/sort -V | /usr/bin/head -n 1)" = "$macports_have" ]; then
        macports_install=1
      fi
    fi
    if [ "$macports_install" = 1 ]; then
      if /usr/sbin/installer -pkg ${pkg} -target /; then
        /usr/bin/touch "$macports_prefix/.anix-pkg-588f14cc"
      else
        echo "macports: pkg install failed; rerun: sudo installer -pkg ${pkg} -target /" >&2
      fi
    fi

    if [ -x "$macports_prefix/bin/port" ]; then
      # Refresh the port index only. selfupdate rebuilds MacPorts itself and
      # can take minutes, so a stale index wins over a failed switch.
      if ! ${lib.getExe' pkgs.coreutils "timeout"} 300 "$macports_prefix/bin/port" sync; then
        echo "macports: port sync failed; run: sudo port sync" >&2
      fi
    fi

    # The shim serves brew's layout out of the MacPorts prefix, so mirror each
    # installed port as <prefix>/Cellar/<name>/<version> and <prefix>/opt/<name>.
    # Both are symlinks to the prefix, where the real files live.
    if macports_installed=$("$macports_prefix/bin/port" -q installed 2>/dev/null); then
      /bin/mkdir -p "$macports_prefix/Cellar" "$macports_prefix/opt"
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
        macports_cellar="$macports_prefix/Cellar/$macports_name"
        /bin/mkdir -p "$macports_cellar"
        /bin/ln -sfn "$macports_prefix" "$macports_cellar/$macports_version"
        /bin/ln -sfn "$macports_prefix" "$macports_prefix/opt/$macports_name"
      done < "$macports_map"
      # Drop links for ports or versions that are no longer installed; every
      # link points at the prefix itself, so a target test cannot detect this.
      for macports_link in "$macports_prefix"/opt/*; do
        [ -L "$macports_link" ] || continue
        macports_name=''${macports_link##*/}
        /usr/bin/awk -v n="$macports_name" '$1 == n { found = 1 } END { exit !found }' "$macports_map" ||
          /bin/rm -f "$macports_link"
      done
      for macports_cellar in "$macports_prefix"/Cellar/*; do
        [ -d "$macports_cellar" ] || continue
        macports_name=''${macports_cellar##*/}
        for macports_link in "$macports_cellar"/*; do
          [ -L "$macports_link" ] || continue
          macports_version=''${macports_link##*/}
          /usr/bin/awk -v n="$macports_name" -v v="$macports_version" \
            '$1 == n && $2 == v { found = 1 } END { exit !found }' "$macports_map" ||
            /bin/rm -f "$macports_link"
        done
        /bin/rmdir "$macports_cellar" 2>/dev/null || true
      done
      /bin/rm -f "$macports_map"
    else
      echo "macports: port -q installed failed; leaving the brew-shaped tree alone" >&2
    fi
  '');
}
