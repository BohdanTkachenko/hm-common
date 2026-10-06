{ lib, ... }:
{
  imports = [
    ./modules/anti-drift.nix
    ./modules/options.nix
  ];

  anti-drift.driftDir = lib.mkDefault "$HOME/Projects/nix-home/personal/drifts";

  # Compatibility baseline; individual homes can override it.
  home.stateVersion = lib.mkDefault "26.05";
  programs.home-manager.enable = true;
  targets.genericLinux.enable = true;
}
