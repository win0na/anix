{
  description = "anix: one flake for anix (NixOS-WSL) and amac (nix-darwin)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-2605.url = "github:NixOS/nixpkgs/nixos-26.05";

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs-2605";
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager-2605 = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-2605";
    };

    # Each host follows its own nixpkgs channel, so sops-nix is pinned twice:
    # anix tracks unstable and amac tracks 26.05.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix-2605 = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs-2605";
    };

    nix-homebrew = {
      url = "github:zhaofengli/nix-homebrew";
    };

    herdr-src = {
      url = "github:kitknox/herdr/rootshell-v0.1.10";
      flake = false;
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-2605, nix-darwin, ... }:
    let
      users = import ./users.nix;
      lib = nixpkgs.lib;
      projectsDir =
        let
          anixHome = "/home/${users.anix}";
          raw = users.projectsDir or "src";
          value = if raw == "/" then raw else lib.removeSuffix "/" raw;
          segments = lib.filter (segment: segment != "") (lib.splitString "/" value);
          # A hidden segment could export a key directory; a protected name
          # could put the Mac mount over a system folder.
          hiddenSegment = lib.any (segment: lib.hasPrefix "." segment) segments;
          blocked = [
            "applications"
            "desktop"
            "documents"
            "downloads"
            "library"
            "movies"
            "music"
            "pictures"
            "public"
            "system"
            "users"
          ];
          blockedSegment = lib.any (segment: lib.elem (lib.toLower segment) blocked) segments;
          underHome = lib.hasPrefix "${anixHome}/" value;
          underMnt = lib.hasPrefix "/mnt/" value
            && builtins.match "/mnt/[A-Za-z](/.*)?" value == null
            && builtins.match "/mnt/(wsl|wslg)(/.*)?" value == null;
        in
        if value == "" then
          "src"
        else if value == "/" then
          throw "projectsDir must not be /"
        else if lib.hasInfix "//" value then
          throw "projectsDir must not contain empty segments: ${value}"
        else if builtins.match "[A-Za-z0-9._/-]+" value == null then
          throw "projectsDir must use only letters, digits, dot, underscore, dash and slash: ${value}"
        else if hiddenSegment then
          throw "projectsDir must not contain a hidden segment: ${value}"
        else if value == anixHome then
          throw "projectsDir must not be the anix home: ${value}"
        else if blockedSegment then
          throw "projectsDir must not use a protected directory name: ${value}"
        else if lib.hasPrefix "/" value && !(underHome || underMnt) then
          throw "projectsDir must be under ${anixHome} or /mnt/<name>: ${value}"
        else
          value;

      darwinFor = hostSystem: nix-darwin.lib.darwinSystem {
        system = hostSystem;
        modules = [ ./hosts/amac ];
        specialArgs = {
          inherit inputs hostSystem projectsDir;
          userName = users.amac;
        };
      };
    in
    {
      nixosConfigurations.anix = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/anix ];
        specialArgs = {
          inherit inputs projectsDir;
          userName = users.anix;
          macUserName = users.amac;
        };
      };

      darwinConfigurations.amac = darwinFor "aarch64-darwin";
      darwinConfigurations.amac-intel = darwinFor "x86_64-darwin";

      overlays.default = import ./overlays;

      packages =
        let
          herdrOverlay = import ./overlays/herdr.nix { inherit (inputs) herdr-src; };
          overlays = [
            inputs.rust-overlay.overlays.default
            herdrOverlay
            (import ./overlays/default.nix)
          ];
          pkgsFor = channel: system: import channel { inherit system overlays; };
        in
        {
          x86_64-linux.fff-mcp = (pkgsFor nixpkgs "x86_64-linux").fff-mcp;
          x86_64-linux.herdr = (pkgsFor nixpkgs "x86_64-linux").herdr;
          x86_64-linux.herdr-sidebar = (pkgsFor nixpkgs "x86_64-linux").herdr-sidebar;
          x86_64-linux.ttt = (pkgsFor nixpkgs "x86_64-linux").ttt;
          aarch64-darwin.brew-shim = (pkgsFor nixpkgs-2605 "aarch64-darwin").brew-shim;
          aarch64-darwin.fff-mcp = (pkgsFor nixpkgs-2605 "aarch64-darwin").fff-mcp;
          aarch64-darwin.herdr = (pkgsFor nixpkgs-2605 "aarch64-darwin").herdr;
          aarch64-darwin.herdr-sidebar = (pkgsFor nixpkgs-2605 "aarch64-darwin").herdr-sidebar;
          aarch64-darwin.ttt = (pkgsFor nixpkgs-2605 "aarch64-darwin").ttt;
          x86_64-darwin.brew-shim = (pkgsFor nixpkgs-2605 "x86_64-darwin").brew-shim;
          x86_64-darwin.fff-mcp = (pkgsFor nixpkgs-2605 "x86_64-darwin").fff-mcp;
          x86_64-darwin.herdr = (pkgsFor nixpkgs-2605 "x86_64-darwin").herdr;
          x86_64-darwin.herdr-sidebar = (pkgsFor nixpkgs-2605 "x86_64-darwin").herdr-sidebar;
          x86_64-darwin.ttt = (pkgsFor nixpkgs-2605 "x86_64-darwin").ttt;
        };

      checks = { };
    };
}
