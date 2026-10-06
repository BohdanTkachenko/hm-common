{ pkgs, ... }:
let
  pinnedNixIde = pkgs.vscode-utils.buildVscodeMarketplaceExtension {
    mktplcRef = {
      publisher = "jnoortheen";
      name = "nix-ide";
      version = "0.5.7";
      sha256 = "sha256-6wIjuvMlA+mwg5gzctkfOAdaQLBy2K6YcV3kJxK3VOo=";
    };
  };
in
with pkgs.nix-vscode-extensions.vscode-marketplace;
[
  coolbear.systemd-unit-file
  davidanson.vscode-markdownlint
  foxundermoon.shell-format
  github.vscode-github-actions
  pinnedNixIde
  mkhl.direnv
  ms-dotnettools.csharp
  ms-python.black-formatter
  ms-python.python
  ms-vscode.cpptools-extension-pack
  ms-vscode.makefile-tools
  ms-vscode-remote.remote-ssh
  puppet.puppet-vscode
  thenuprojectcontributors.vscode-nushell-lang
  jj-view.jj-view
  yzhang.markdown-all-in-one
]
