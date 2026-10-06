{ config, lib, ... }:
{
  options.my.cargo.registryTokenFile = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    example = "/run/user/1000/secrets/cargo-registry-token";
    description = ''
      Path to a file containing the crates.io publish token. When set, it is
      exported into the interactive shell as CARGO_REGISTRY_TOKEN (which
      `cargo publish` reads). Point it at a secret manager's decrypted file so
      no token lands in the world-readable Nix store.
    '';
  };

  config = lib.mkIf (config.my.cargo.registryTokenFile != null) {
    programs.fish.interactiveShellInit = ''
      if test -r "${config.my.cargo.registryTokenFile}"
        set -gx CARGO_REGISTRY_TOKEN (cat "${config.my.cargo.registryTokenFile}")
      end
    '';
  };
}
