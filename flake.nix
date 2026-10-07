{
  description = "Home Manager configuration shared by Dan's personal and work machines";

  # Public by design: everything here must be safe on a work machine (Google
  # models only — Antigravity is the one agent tool) and free of anything
  # private. checks.work-safe-home and checks.no-other-ai guard that.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # antigravity-ide — fork branch merging the antigravity-ide package (+ NixOS
    # agent fix) with the vscode-with-extensions iconName fix
    # (https://github.com/NixOS/nixpkgs/pull/526069)
    # Rev-pinned rather than tracking the branch: the nightly bump would
    # otherwise pick up pushes silently, and a bad one breaks eval for every
    # host at once. Bump deliberately when you push to the fork.
    nixpkgs-antigravity-ide.url = "github:BohdanTkachenko/nixpkgs/606c34980dc3db8f0f367a74f5e7c8daf848f24b";

    # antigravity-hub — https://github.com/NixOS/nixpkgs/pull/524225
    # Rev-pinned, not pull/524225/head: that ref moves on unreviewed author
    # pushes and a bad one breaks eval everywhere.
    nixpkgs-antigravity-hub.url = "github:NixOS/nixpkgs/4894041b0b999e8c7f7d43589de17c03d45ff9f3";

    # antigravity-cli — https://github.com/NixOS/nixpkgs/pull/526033, which is
    # CLOSED; this input is frozen dead weight and a candidate for removal.
    # Rev-pinned for the same reason as the others.
    nixpkgs-antigravity-cli.url = "github:NixOS/nixpkgs/0338e9e3c71d8458d599dbd7776678d220949ed8";

    # Only used by the checks; consumers bring their own home-manager.
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Pinned to a rev, not a branch: a broken xremap means no keyboard
    # remapping on a machine you may be sitting at. Upstream publishes no
    # tags, so this is a bare rev — bump it by hand when you can test it.
    xremap = {
      url = "github:xremap/nix-flake/7f161bede2961279dfde194add6aa53d80a9d26d";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    chromium-pwa-wmclass-sync = {
      url = "github:BohdanTkachenko/chromium-pwa-wmclass-sync";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    direnv-instant = {
      url = "github:Mic92/direnv-instant";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      nixpkgs-antigravity-ide,
      nixpkgs-antigravity-hub,
      nixpkgs-antigravity-cli,
      home-manager,
      nix-vscode-extensions,
      xremap,
      chromium-pwa-wmclass-sync,
      direnv-instant,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # Module arguments the modules expect, per system. They cannot be set
      # from inside a module (nixpkgs.overlays reads them, which would
      # recurse), so consumers pass them as extraSpecialArgs.
      mkSpecialArgs = system: {
        inherit nix-vscode-extensions;
        pkgs-antigravity-ide = import nixpkgs-antigravity-ide {
          inherit system;
          config.allowUnfree = true;
        };
        pkgs-antigravity-hub = import nixpkgs-antigravity-hub {
          inherit system;
          config.allowUnfree = true;
        };
        pkgs-antigravity-cli = import nixpkgs-antigravity-cli {
          inherit system;
          config.allowUnfree = true;
        };
        pkgs-unstable = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            # openldap's syncreplication test (test017) is flaky upstream and
            # blocks rebuilds whenever pkgs-unstable rolls past a cache miss.
            # The test isn't load-bearing for our use of openldap as a
            # transitive dep — skip it.
            (_: prev: {
              openldap = prev.openldap.overrideAttrs (_: {
                doCheck = false;
              });
            })
          ];
        };
      };

      # Third-party Home Manager modules the profiles configure.
      externalModules = [
        chromium-pwa-wmclass-sync.homeManagerModules.default
        direnv-instant.homeModules.direnv-instant
        xremap.homeManagerModules.default
      ];
    in
    {
      lib = { inherit mkSpecialArgs; };

      # Building blocks, without the third-party modules or the overlays.
      homeManagerModules.portable = import ./home/profiles/portable.nix;
      homeManagerModules.base = import ./home/profiles/base.nix;
      homeManagerModules.cli = import ./home/profiles/cli.nix;
      homeManagerModules.gui = import ./home/profiles/gui.nix;

      # Everything shared by every machine: CLI, GUI (behind my.gui.enable),
      # Antigravity, hardware helpers, overlays. Needs mkSpecialArgs.
      homeManagerModules.common =
        { pkgs, ... }:
        let
          args = mkSpecialArgs pkgs.stdenv.hostPlatform.system;
        in
        {
          # Fallbacks for consumers that pass no extraSpecialArgs; overlays
          # still need nix-vscode-extensions as a special arg.
          _module.args = {
            inherit (args)
              pkgs-unstable
              pkgs-antigravity-ide
              pkgs-antigravity-hub
              pkgs-antigravity-cli
              nix-vscode-extensions
              ;
          };
          imports = externalModules ++ [
            ./overlays
            ./home/hardware
            ./home/profiles/common.nix
          ];
        };
      homeManagerModules.default = self.homeManagerModules.common;

      # The overlays as a module (works in NixOS and Home Manager alike).
      nixosModules.overlays = ./overlays;
      overlays.jj-worktree = final: _prev: {
        jj-worktree = final.callPackage ./overlays/jj-worktree.nix { };
      };

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          antigravity-standalone = import ./tests/antigravity-standalone.nix {
            inherit pkgs home-manager;
          };
          work-safe-home = import ./tests/work-safe-home.nix {
            inherit self pkgs home-manager;
            lib = pkgs.lib;
            extraSpecialArgs = mkSpecialArgs system;
          };
          no-other-ai = import ./tests/no-other-ai.nix {
            inherit pkgs;
            src = self;
          };
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}
