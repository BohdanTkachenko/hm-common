{
  lib,
  pkgs-unstable,
  # Optional so consumers without the antigravity package set (work machines)
  # still evaluate; ask is simply omitted there.
  pkgs-antigravity-cli ? null,
  ...
}:

let
  mkAskAiScript =
    {
      name,
      exe,
      args,
    }:
    pkgs-unstable.writeShellScriptBin name ''
      TOOL="${exe}"
      STDERR_LOG="/tmp/${name}.error.log"
      DEFAULT_INSTRUCTION="Help me understand this input."
      ARGS=(${builtins.concatStringsSep " " (map (a: "'${a}'") args)})

      if [ $# -gt 0 ]; then
        instruction="$*"
      else
        instruction="''${DEFAULT_INSTRUCTION}"
      fi

      generate_input() {
        printf "## Request\n%s\n\n" "''${instruction}"

        if [ ! -t 0 ]; then
          printf "%b" "---\n\n## Input Data\n"
          cat -
        fi
      }

      if [ $# -eq 0 ] && [ -t 0 ]; then
        echo "Usage: ${name} [prompt]"
        echo "       ${name} [custom instruction] < stdin"
        echo "       ${name} < stdin"
        exit 1
      fi

      generate_input \
      | "$TOOL" "''${ARGS[@]}" 2> "$STDERR_LOG" \
      | "${pkgs-unstable.glow}/bin/glow"
    '';

  # `ask` = Antigravity CLI: fast to first token for one-shot
  # answers. `agy -p` takes the instruction as an argument (it does
  # NOT read a bare-stdin prompt) but still sees piped stdin as context, so a
  # fixed meta-instruction points it at the request/data document
  # generate_input pipes in. No quotes in the string — ARGS wraps each arg in
  # single quotes.
  ask =
    if pkgs-antigravity-cli != null then
      mkAskAiScript {
        name = "ask";
        exe = "${pkgs-antigravity-cli.antigravity-cli}/bin/agy";
        args = [
          "-p"
          "Respond to the piped input: answer its ## Request, using its ## Input Data section if present. Output only the response, no preamble."
        ];
      }
    else
      null;

in
{
  home.packages = lib.optional (ask != null) ask;
}
