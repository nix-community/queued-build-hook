{ pkgs ? import <nixpkgs> { }
, lib ? pkgs.lib
}:

pkgs.buildGoModule rec {
  name = "queued-build-hook-${version}";
  version = "git";

  src = lib.cleanSource ./.;
  vendorHash = null;

  meta = {
    description = "Queue and retry Nix post-build-hook";
    homepage = "https://github.com/nix-community/queued-build-hook";
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.adisbladis ];
  };

}
