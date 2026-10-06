{ config, pkgs, ... }:
{
  programs.git = {
    enable = true;

    signing = {
      key = "~/.ssh/id_ed25519";
      signByDefault = true;
    };

    settings = {
      user = {
        name = config.my.identity.name;
        email = config.my.identity.email;
      };

      gpg = {
        format = "ssh";
      };

      core = {
        editor = "micro";
      };

      init = {
        defaultBranch = "main";
      };

      push = {
        autoSetupRemote = true;
      };

      pull = {
        rebase = true;
      };

      url = {
        "git@github.com:" = {
          pushInsteadOf = "https://github.com/";
        };
      };
    };
  };
}
