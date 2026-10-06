{ ... }:
{
  nixpkgs.overlays = [
    (final: prev: {
      riff = final.callPackage ./riff.nix { };
    })
  ];
}
