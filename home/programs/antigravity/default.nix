{ ... }:
{
  # CLI + MCP + shared config are headless-safe; the Hub and IDE are graphical
  # and gate their own effect on my.gui.enable.
  imports = [
    ./common.nix
    ./cli.nix
    ./mcp.nix
    ./hub.nix
    ./ide.nix
  ];
}
