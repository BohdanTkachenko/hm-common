# hm-common

Home Manager configuration shared by all of my machines — personal NixOS hosts
and the Debian work machines that run standalone Home Manager. It holds only
what is common to both: CLI tools and shell setup, GUI apps behind
`my.gui.enable`, Antigravity, hardware helpers, and overlays. Anything personal
(secrets, other agent tooling, host-specific config) lives in a private flake
that imports this one.

## Use

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hm-common = {
      url = "github:BohdanTkachenko/hm-common";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = { nixpkgs, home-manager, hm-common, ... }:
    let
      system = "x86_64-linux";
    in
    {
      homeConfigurations.me = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        # pkgs-unstable, the Antigravity package sets, nix-vscode-extensions.
        extraSpecialArgs = hm-common.lib.mkSpecialArgs system;
        modules = [
          hm-common.homeManagerModules.default
          {
            home.username = "me";
            home.homeDirectory = "/home/me";
            my.gui.enable = false; # headless: terminal tools + Antigravity CLI only
            my.identity.email = "me@example.com";
          }
        ];
      };
    };
}
```

## Outputs

- `homeManagerModules.default` (= `common`) — everything above, including the
  third-party modules it configures and the overlays.
- `homeManagerModules.{portable,base,cli,gui}` — building blocks without the
  third-party modules or overlays (`portable` also works on macOS).
- `lib.mkSpecialArgs system` — the module arguments the modules expect.
- `nixosModules.overlays` — the overlays as a module, for NixOS hosts with
  `home-manager.useGlobalPkgs`.

## Self-updating Antigravity CLI

Linux consumers can set `my.antigravity.cli.standalone.enable = true` to use
the native self-updating CLI. A user service bootstraps the executable from
the official release manifest and verifies its SHA512 checksum. The mutable
binary lives in `~/.local/share/antigravity-cli/agy`; the managed `agy` launcher
is available through both the Home Manager profile and `~/.local/bin`.
Shell profiles and existing CLI settings are preserved, and `ask` uses the
same launcher. The default remains the Nix-packaged CLI.
NixOS consumers need `programs.nix-ld.enable = true` for the native binary.

## Checks

`nix flake check` runs:

- `work-safe-home` — the evaluated profile installs no non-Google AI tooling
  and no host-specific SSH config.
- `no-other-ai` — no file mentions other AI tooling or private addresses.
- `antigravity-standalone` — verifies checksum rejection, safe replacement,
  launcher routing, and idempotent installation without network access.
