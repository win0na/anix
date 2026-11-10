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
      inputs.nixpkgs.follows = "nixpkgs-2605";
    };

    herdr-src = {
      url = "github:kitknox/herdr/rootshell-v0.1.10";
      flake = false;
    };
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-2605, nix-darwin, ... }:
    {
      nixosConfigurations.anix = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/anix ];
        specialArgs = { inherit inputs; };
      };

      darwinConfigurations.amac = nix-darwin.lib.darwinSystem {
        system = "x86_64-darwin";
        modules = [ ./hosts/amac ];
        specialArgs = { inherit inputs; };
      };

      overlays.default = import ./overlays;

      # TODO: packages, checks, and module wiring land in the configuration pass.
      checks = { };
      packages = { };
    };
}
