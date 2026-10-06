# This repo is consumed by work machines where only Google models are allowed:
# no file may mention other AI tooling, and none may carry private network
# addresses. (The owner's private config separately scans this source for its
# own host and account names.) Patterns are case-insensitive.
{ pkgs, src }:
pkgs.runCommand "no-other-ai"
  {
    nativeBuildInputs = [ pkgs.ripgrep ];
  }
  ''
    cd ${src}
    # tests/ spells the patterns out.
    if rg --ignore-case --line-number --glob '!tests/**' \
        -e 'anthropic|claude|openai|codex|chatgpt|opencode' \
        -e '\b100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.|\b10\.[0-9]+\.[0-9]+\.|\b192\.168\.' \
        .; then
      echo "other-AI or private-address references found (above)" >&2
      exit 1
    fi
    touch $out
  ''
