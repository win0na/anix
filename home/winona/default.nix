{ ... }:

{
  imports = [
    ./herdr
    ./opencode
    ./ttt
  ];

  home.username = "winona";
  home.sessionPath = [ "$HOME/.local/bin" ];

  # TODO: shared packages, aliases, prompt.
}
