{ self }:
_final: prev: {
  queued-build-hook = self.packages.${prev.system}.queued-build-hook;
}
