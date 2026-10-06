{ config, lib, ... }:
let
  langs = [
    "buf"
    "bun"
    "c"
    "cmake"
    "cobol"
    "conda"
    "cpp"
    "crystal"
    "daml"
    "dart"
    "deno"
    "docker_context"
    "dotnet"
    "elixir"
    "elm"
    "fennel"
    "gleam"
    "golang"
    "gradle"
    "haskell"
    "haxe"
    "helm"
    "java"
    "julia"
    "kotlin"
    "lua"
    "mojo"
    "nim"
    "nodejs"
    "ocaml"
    "odin"
    "opa"
    "package"
    "perl"
    "php"
    "pixi"
    "purescript"
    "quarto"
    "raku"
    "red"
    "rlang"
    "ruby"
    "rust"
    "scala"
    "solidity"
    "spack"
    "swift"
    "terraform"
    "typst"
    "vagrant"
    "vlang"
    "zig"
  ];
in
{
  imports = [ ./icons.nix ];

  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    settings = {
      format = lib.concatStrings [
        "$os"
        "$nix_shell"
        "$username"
        "$hostname"
        "$localip"
        "$shlvl"
        "$directory"
        "\${custom.jj}"
        "\${custom.git_branch}"
        "\${custom.git_commit}"
        "$git_state"
        "\${custom.git_metrics}"
        "\${custom.git_status}"
        "$hg_branch"
        "$hg_state"
        "$jobs"
        "$character"
      ];

      right_format = lib.concatStrings [
        "$status"
        "$cmd_duration"
        "\${custom.jj_descr}\n"
        "$python"
        (lib.concatStrings (map (lang: "$" + lang) langs))
        "$memory_usage"
        "$direnv"
        "$battery"
        "$time"
        "$container"
      ];

      hostname = {
        format = "[@$hostname]($style)[:](bright-black) ";
        aliases = {
          dan = "ws";
        };
      };

      username.format = "[$user]($style)";

      directory = {
        truncation_length = 2;
        truncate_to_repo = false;
        substitutions = { };
      };

      cmd_duration = {
        format = "[󰔟 $duration]($style) ";
      };

      time = {
        disabled = false;
        format = "[$time](bright-black) ";
      };

      direnv.disabled = false;
      status.disabled = false;

      os = {
        disabled = false;
        style = "bold bright-black";
      };

      python.format = "[$symbol$virtualenv]($style) ";
      git_branch.format = "[$symbol$branch(:$remote_branch)]($style) ";

      custom.jj = {
        description = "The current jj status";
        when = "jj --ignore-working-copy root";
        symbol = " ";
        command = ''
          jj log --revisions @ --no-graph --ignore-working-copy --color always --limit 1 --template '
            separate(" ",
              change_id.shortest(4),
              bookmarks,
              concat(
                if(conflict, "󰞇"),
                if(divergent, "󰃻"),
                if(hidden, ""),
                if(immutable, ""),
              ) ++ raw_escape_sequence("\x1b[0m"),
            )
          '
        '';
        ignore_timeout = true;
      };

      custom.jj_descr = {
        description = "The current jj commit description";
        when = "jj --ignore-working-copy root";
        symbol = "󰜛 ";
        command = ''
          jj log --revisions @ --no-graph --ignore-working-copy --color always --limit 1 --template '
            separate(" ",
              raw_escape_sequence("\x1b[1;32m") ++ if(empty, "(empty)"),
              raw_escape_sequence("\x1b[1;32m") ++ coalesce(
                truncate_end(29, description.first_line(), "…"),
                "(no description set)",
              ) ++ raw_escape_sequence("\x1b[0m"),
            )
          '
        '';
        ignore_timeout = true;
      };

      git_status.disabled = true;
      custom.git_status = {
        when = "! jj --ignore-working-copy root";
        require_repo = true;
        command = "starship module git_status";
        style = ""; # This disables the default "(bold green)" style
        description = "Only show git_status if we're not in a jj repo";
      };

      git_commit.disabled = true;
      custom.git_commit = {
        when = "! jj --ignore-working-copy root";
        require_repo = true;
        command = "starship module git_commit";
        style = "";
        description = "Only show git_commit if we're not in a jj repo";
      };

      git_metrics.disabled = true;
      custom.git_metrics = {
        when = "! jj --ignore-working-copy root";
        require_repo = true;
        command = "starship module git_metrics";
        description = "Only show git_metrics if we're not in a jj repo";
        style = "";
      };

      git_branch.disabled = true;
      custom.git_branch = {
        when = "! jj --ignore-working-copy root";
        require_repo = true;
        command = "starship module git_branch";
        description = "Only show git_branch if we're not in a jj repo";
        style = "";
      };
    }

    # Only show lang icons, if detected.
    // (lib.genAttrs langs (name: {
      format = "[$symbol]($style)";
    }));
  };
}
