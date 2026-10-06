{ ... }:
{
  imports = [
    ./base.nix
    ./cli.nix
    ./gui.nix
    # Antigravity is the one agent tool allowed on the work machines (Google
    # models only); any other agent tooling belongs in the consumer's config.
    ../programs/antigravity
  ];
}
