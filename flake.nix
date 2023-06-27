{
  description = "Asynchronous Nix post-build-hook";

  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    devshell = {
      url = "github:numtide/devshell";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  };

  outputs = { self, nixpkgs, flake-utils, devshell, treefmt-nix, pre-commit-hooks }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
    in
    {
      nixosModules.queued-build-hook = import ./module.nix;
      overlays.default = import ./overlay.nix { inherit self; };
    } // flake-utils.lib.eachSystem supportedSystems (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ devshell.overlays.default ];
        };
        # treefmt-nix configuration
        packages = {
          queued-build-hook = pkgs.callPackage ./. { };
        };


        treefmt = (treefmt-nix.lib.mkWrapper pkgs
          {
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
          });
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
            treefmt
          ];
          devshell.startup.pre-commit.text = self.checks.${system}.pre-commit-check.shellHook;
          env = [
            {
              name = "DEVSHELL_NO_MOTD";
              value = "1";
            }
          ];
          commands = [
            {
              name = "fmt";
              help = "Format code";
              command = "${treefmt}/bin/treefmt";
            }
            {
              name = "check";
              help = "Check the code";
              command = "${pkgs.pre-commit}/bin/pre-commit run --all";
            }
            {
              name = "lint";
              help = "Lint the code";
              command = "${pkgs.golangci-lint}/bin/golangci-lint run";
            }
          ];

        };
        checks = {
          shell = self.devShells.${system}.default;
          pre-commit-check = pre-commit-hooks.lib.${system}.run
            {
              src = ./.;
              hooks = {
                treefmt-check =
                  {
                    enable = true;
                    entry = "${treefmt}/bin/treefmt --fail-on-change";
                    pass_filenames = false;
                  };
              };
            };
        } // import ./tests { inherit pkgs system; };

        formatter = treefmt;

        apps.default = { type = "app"; program = "${self.packages.${system}.queued-build-hook}/bin/queued-build-hook"; };
      });
}
