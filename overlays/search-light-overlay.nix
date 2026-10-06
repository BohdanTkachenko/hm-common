{ ... }:
{
  nixpkgs.overlays = [
    (final: prev: {
      gnomeExtensions = prev.gnomeExtensions // {
        search-light = final.callPackage ./search-light.nix { };
      };
    })
  ];
}
