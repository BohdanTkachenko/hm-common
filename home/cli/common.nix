{ ... }:
{
  imports = [
    ./portable.nix
    ../programs/containers.nix
    ../programs/direnv.nix
    ../programs/dotfiles.nix
    ../programs/ai/ask.nix
    ../programs/audio-fix.nix
  ];
}
