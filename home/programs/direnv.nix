{ config, lib, ... }:
{
  imports = [ ./direnv-core.nix ];

  programs.direnv-instant.enable = lib.mkIf config.my.direnv-instant.enable true;

  # The direnv package ships share/fish/vendor_conf.d/direnv.fish, which
  # unconditionally registers the classic synchronous hook in every fish.
  # enableFishIntegration = false (forced by the direnv-instant module) only
  # governs HM's own hook line, not the vendor file — so both hooks end up
  # live and the classic one still blocks the prompt on every .envrc/flake
  # change, defeating direnv-instant. Shadow the vendor snippet with an empty
  # user conf.d file: fish sources only the first file of a given basename,
  # and user config dirs come before vendor dirs.
  xdg.configFile."fish/conf.d/direnv.fish" = lib.mkIf config.my.direnv-instant.enable {
    text = "";
  };
}
