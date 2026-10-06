{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bat
    btop
    eza
    fd
    gh
    nushell
    procs
    ripgrep
    sox
    trash-cli
    ugrep
    xh
    yq
  ];

  imports = [
    ../programs/bash.nix
    ../programs/cargo.nix
    ../programs/fish.nix
    ../programs/git.nix
    ../programs/jujutsu.nix
    ../programs/micro.nix
    ../programs/ssh
    ../programs/starship
    ../programs/tealdeer.nix
    ../programs/direnv-core.nix
  ];
}
