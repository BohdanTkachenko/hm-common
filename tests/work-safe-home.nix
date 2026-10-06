# The exported homeManagerModules.common is what Dan's work machines (Google)
# import. It must carry no non-Google AI tooling (only Google models are
# allowed there) and no host-specific SSH config.
# Evaluation-only: fails at `nix flake check` time, builds nothing heavy.
{
  self,
  pkgs,
  lib,
  home-manager,
  extraSpecialArgs,
}:
let
  # Like any real consumer: the modules install unfree apps (Spotify, Chrome).
  hmPkgs = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
  eval = home-manager.lib.homeManagerConfiguration {
    pkgs = hmPkgs;
    inherit extraSpecialArgs;
    modules = [
      self.homeManagerModules.common
      {
        home.username = "worksafe";
        home.homeDirectory = "/home/worksafe";
        my.gui.enable = true;
      }
    ];
  };
  cfg = eval.config;

  forbidden = "(anthropic|claude|openai|codex|chatgpt|opencode)";
  matches = re: s: builtins.match ".*${re}.*" (lib.toLower s) != null;

  packageNames = map (p: p.name or (toString p)) cfg.home.packages;
  vscodeExtensions = lib.concatMap (
    prof: map (e: e.vscodeExtUniqueId or e.name or (toString e)) (prof.extensions or [ ])
  ) (lib.attrValues (cfg.programs.vscode.profiles or { }));
  userServices = lib.attrNames cfg.systemd.user.services ++ lib.attrNames cfg.systemd.user.timers;
  sshHosts = lib.attrNames (cfg.programs.ssh.settings or { });

  violations =
    map (n: "package: ${n}") (lib.filter (matches forbidden) packageNames)
    ++ map (n: "vscode extension: ${n}") (lib.filter (matches forbidden) vscodeExtensions)
    ++ map (n: "user unit: ${n}") (
      lib.filter (n: matches forbidden n || matches "nh-pull" n) userServices
    )
    ++ map (n: "ssh host: ${n}") (lib.filter (n: n != "*") sshHosts);
in
if violations == [ ] then
  pkgs.runCommand "work-safe-home" { } ''
    echo "checked ${toString (lib.length packageNames)} packages, ${toString (lib.length vscodeExtensions)} VS Code extensions, ${toString (lib.length userServices)} user units, ${toString (lib.length sshHosts)} ssh hosts" > $out
  ''
else
  throw ''
    homeManagerModules.common is not work-safe:
      ${lib.concatStringsSep "\n  " violations}
  ''
