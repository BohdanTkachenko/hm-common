{ ... }:
{
  # No host paths, state version, genericLinux target, or desktop services.
  # Consumers supply pkgs-unstable for Jujutsu (their native pkgs is also fine).
  imports = [
    ../modules/options.nix
    ../cli/portable.nix
  ];
}
