{ nix-vscode-extensions, ... }:
{
  nixpkgs.overlays = [
    nix-vscode-extensions.overlays.default
  ];

  imports = [
    ../home/modules/options.nix
    ./google-chrome.nix
    ./riff-overlay.nix
    ./search-light-overlay.nix
  ];
}
