{ ... }:
{
  xdg.configFile."containers/policy.json".text = builtins.toJSON {
    default = [ { type = "insecureAcceptAnything"; } ];
  };

  xdg.configFile."containers/storage.conf".text = ''
    [storage]
    driver = "overlay"
    [storage.options]
    ignore_chown_errors = "true"
  '';
}
