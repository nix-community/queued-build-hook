{ pkgs, system }:
let
  lib = pkgs.lib;

  # Find all the nix files defining tests
  allTestFiles =
    lib.mapAttrs' (filename: _: lib.nameValuePair (lib.removeSuffix ".nix" filename) filename) (
      lib.filterAttrs
        (name: _: lib.hasSuffix ".nix" name && name != "default.nix")
        (builtins.readDir ./.));

  mkTest = fileName: import (./. + "/${fileName}") { inherit pkgs system; };
in
if pkgs.stdenv.isLinux then
  lib.mapAttrs (_: mkTest) allTestFiles
else { }
