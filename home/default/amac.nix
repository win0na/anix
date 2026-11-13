{ userName, lib, ... }:

let
  builderKey = "";
in
{
  home.homeDirectory = "/Users/${userName}";
  home.stateVersion = "26.05";

  # Append the builder key without replacing keys that already exist.
  # An empty key installs nothing, so a fresh fork does not touch authorized_keys.
  home.activation.installAnixBuilderKey = lib.mkIf (builderKey != "") (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    key=${lib.escapeShellArg builderKey}
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    touch "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
    if ! grep -qxF "$key" "$HOME/.ssh/authorized_keys"; then
      [ -z "$(tail -c 1 "$HOME/.ssh/authorized_keys")" ] || printf '\n' >> "$HOME/.ssh/authorized_keys"
      printf '%s\n' "$key" >> "$HOME/.ssh/authorized_keys"
    fi
  '');
}
