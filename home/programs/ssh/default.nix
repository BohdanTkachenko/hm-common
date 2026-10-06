{ ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    settings = {
      # Default host config (required when enableDefaultConfig = false).
      # settings.* is freeform and keyed by ssh_config directive names.
      # Consumers may add system-level ssh config (e.g. for a mesh); ssh reads
      # it after this file and takes the first value per directive, so nothing
      # here may shadow it.
      "*" = {
        ControlMaster = "auto";
        ControlPath = "~/.ssh/ctrl-%C";
        ControlPersist = "yes";
        # Without keepalives a persistent master whose TCP link died (wifi
        # change, suspend) listens forever and every new ssh hangs on its
        # socket. With them the master notices within ~45s, exits, and unlinks
        # the socket, so ControlMaster=auto starts a fresh one.
        ServerAliveInterval = 15;
        ServerAliveCountMax = 3;
      };

    };
  };
}
