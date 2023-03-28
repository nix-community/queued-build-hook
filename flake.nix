{
  description = "Asynchronous Nix post-build-hook";

  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    devshell = {
      url = "github:numtide/devshell";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, devshell, treefmt-nix, ... }: {
    nixosModules.queued-build-hook = import ./module.nix;
    overlays.default = import ./overlay.nix { inherit self; };
  } // flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ devshell.overlays.default ];
      };
      # treefmt-nix configuration
      treefmt.config = {
        projectRootFile = "flake.nix";
        programs = {
          nixpkgs-fmt.enable = true;
          gofumpt.enable = true;
        };
        settings.formatter.deadnix = {
          command = "${pkgs.deadnix}/bin/deadnix";
          options = [ "--edit" ];
          includes = [ "*.nix" ];
        };
      };
    in
    {
      packages = {
        queued-build-hook = pkgs.callPackage ./. { };
      };

      packages.default = self.packages.${system}.queued-build-hook;

      devShells.default = pkgs.devshell.mkShell {
        packages = with pkgs; [
          go
          golangci-lint
          systemfd
          (treefmt-nix.lib.mkWrapper pkgs treefmt.config)
        ];
        env = [
          {
            name = "DEVSHELL_NO_MOTD";
            value = "1";
          }
        ];
      };

      formatter = treefmt-nix.lib.mkWrapper pkgs treefmt.config;

      apps.default = { type = "app"; program = "${self.packages.${system}.queued-build-hook}/bin/queued-build-hook"; };
    });
}
