{ pkgs, ... }:
{
  programs.bash.initExtra = ''
    dotfiles() {
      if [[ "$1" == "cd" ]]; then
        cd "$HOME/Projects/nix-home/personal"
      else
        if [ -e /etc/NIXOS ]; then
          nix-shell -p gnumake --run "make -C $HOME/Projects/nix-home/personal ''$@"
        else
          make -C "$HOME/Projects/nix-home/personal" "$@"
        fi
      fi
    }
  '';

  programs.fish.functions = {
    dotfiles = ''
      if test "$argv[1]" = "cd"
        cd "$HOME/Projects/nix-home/personal"
      else
        if test -e /etc/NIXOS
          nix-shell -p gnumake --run "make -C $HOME/Projects/nix-home/personal $argv"
        else
          make -C "$HOME/Projects/nix-home/personal" $argv
        end
      end
    '';
  };
}
