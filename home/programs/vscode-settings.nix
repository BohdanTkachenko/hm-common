{ pkgs-unstable, ... }:
{
  # Fonts
  "editor.fontFamily" = "'MesloLGL Nerd Font Mono', 'Droid Sans Mono', 'monospace', monospace";
  "editor.fontSize" = 16;
  "terminal.integrated.fontFamily" = "MesloLGL Nerd Font";

  # Disable updates
  "extensions.autoCheckUpdates" = false;
  "extensions.autoUpdate" = "off";
  # "extensions.verifySignature" = false;
  "update.mode" = "none";
  "update.showReleaseNotes" = false;

  # Formatting
  "editor.formatOnSave" = true;
  "[dockerfile]"."editor.defaultFormatter" = "ms-azuretools.vscode-containers";
  "[markdown]"."editor.defaultFormatter" = "yzhang.markdown-all-in-one";

  # General
  "editor.rulers" = [ 80 ];
  "editor.tabSize" = 2;
  "editor.wordWrap" = "on";
  "explorer.confirmDragAndDrop" = false;
  "files.autoSave" = "onFocusChange";
  "workbench.startupEditor" = "none";

  # Extensions
  "puppet.editorService.enable" = false;
  "nushellLanguageServer.nushellExecutablePath" = "${pkgs-unstable.nushell}/bin/nu";
  "jj-view.showSourceControlColocated" = true;
  "security.promptForLocalFileProtocolHandling" = false;
  "rust-analyzer.runnables.command" = "${pkgs-unstable.cargo}/bin/cargo";

  # Nix IDE LSP config
  "nix.enableLSP" = true;
  "nix.serverPath" = "nixd";

  # Other
  "git.enabled" = false;
}
