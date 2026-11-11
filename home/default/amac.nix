{ userName, lib, ... }:

let
  builderKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMrCBmuvJjxzV9XxfxBMdncZsx/JHUGOa3VWdnbtJHOJ anix-builder";
in
{
  home.homeDirectory = "/Users/${userName}";
  home.stateVersion = "26.05";

  # Append the builder key without replacing keys that already exist.
  home.activation.installAnixBuilderKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    key=${lib.escapeShellArg builderKey}
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    touch "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
    grep -qxF "$key" "$HOME/.ssh/authorized_keys" || printf '%s\n' "$key" >> "$HOME/.ssh/authorized_keys"
  '';
}
