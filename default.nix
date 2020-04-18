{
  pkgs ? import <nixpkgs> {}
  , lib ? pkgs.lib
}:

pkgs.buildGoPackage rec {
  name = "queued-build-hook-${version}";
  version = "git";
  goPackagePath = "github.com/nix-community/queued-build-hook";

  src = lib.cleanSource ./.;

  meta = {
    description = "Queue and retry Nix post-build-hook";
    homepage = https://github.com/nix-community/queued-build-hook;
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.adisbladis ];
  };

}
