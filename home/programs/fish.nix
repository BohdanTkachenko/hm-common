{
  config,
  lib,
  pkgs,
  ...
}:

{
  programs.fish = {
    enable = true;

    shellAliases = {
      cat = "bat --no-pager --plain";
      less = "bat --plain";

      l = "eza --extended --icons --hyperlink --group-directories-first -lah";
      t = "l --ignore-glob '.git|.jj' -TL 2";

      grep = "ug";
      egrep = "ug -E";
      fgrep = "ug -F";
      xzgrep = "ug -z";
      xzegrep = "ug -zE";
      xzfgrep = "ug -zF";
    };

    shellAbbrs = {
      tt = "t -L 5";
      ta = "t --absolute=on -L 5";
    };

    functions = {
      nosleep = {
        description = "Run a command with system suspend inhibited for its lifetime";
        body =
          if pkgs.stdenv.hostPlatform.isDarwin then
            ''
              /usr/bin/caffeinate -i $argv
            ''
          else
            ''
              systemd-inhibit --what=idle:sleep --who=nosleep --why="user-requested" --mode=block -- $argv
            '';
      };
    };

    plugins = with pkgs.fishPlugins; [
      {
        name = "sponge";
        inherit (z) src;
      }

      {
        name = "z";
        inherit (z) src;
      }
    ];

    interactiveShellInit = ''
      set -g fish_greeting
      set -g fish_color_command green --bold
      set -g fish_color_end blue

      if set -q SSH_CONNECTION && not set -q SSH_AUTH_SOCK
        echo (set_color yellow)"Warning: SSH_AUTH_SOCK is not set. SSH agent forwarding may not be working."(set_color normal)
      end
    '';
  };
}
