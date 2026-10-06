{
  pkgs-unstable,
  nix-vscode-extensions,
  ...
}:
{
  _module.args = {
    inherit pkgs-unstable nix-vscode-extensions;
  };

  imports = [
    ../modules/options.nix
    ../common.nix
  ];
}
