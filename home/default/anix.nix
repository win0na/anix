{ userName, ... }:

{
  home.homeDirectory = "/home/${userName}";
  home.stateVersion = "26.11";
}
