{ config, lib, ... }:
let
  # ── Master permission definitions (tool-agnostic) ──────────────────────

  # Shell commands: null = allow all subcommands, list = specific subcommands only.
  # This is the single source of truth shared by every agent tool (Antigravity
  # IDE and CLI here; consumers can render it for their own tools).
  commands = {
    # General CLI
    awk = null;
    basename = null;
    cat = null;
    curl = null;
    cut = null;
    date = null;
    diff = null;
    dig = null;
    dirname = null;
    du = null;
    echo = null;
    env = null;
    eza = null;
    fd = null;
    file = null;
    find = null;
    grep = null;
    head = null;
    host = null;
    jq = null;
    ls = null;
    man = null;
    md5sum = null;
    mktemp = null;
    nslookup = null;
    printenv = null;
    readlink = null;
    rg = null;
    sed = null;
    sha256sum = null;
    sort = null;
    stat = null;
    tail = null;
    tee = null;
    tokei = null;
    tr = null;
    tree = null;
    uname = null;
    uniq = null;
    wc = null;
    wget = null;
    which = null;
    yq = null;

    # Cargo (read-only / build)
    cargo = [
      "bench"
      "build"
      "check"
      "clippy"
      "doc"
      "metadata"
      "read-manifest"
      "search"
      "test"
      "tree"
      "verify-project"
    ];

    # Go (read-only / build)
    go = [
      "build"
      "doc"
      "env"
      "list"
      "mod graph"
      "mod verify"
      "test"
      "version"
      "vet"
    ];

    # GitHub CLI (read-only)
    gh = [
      "api"
      "issue list"
      "issue status"
      "issue view"
      "pr checks"
      "pr diff"
      "pr list"
      "pr status"
      "pr view"
      "repo list"
      "repo view"
      "run list"
      "run view"
      "search"
      "status"
    ];

    # Git (read-only)
    git = [
      "blame"
      "diff"
      "log"
      "show"
      "status"
    ];

    # npm (read-only / build)
    npm = [
      "audit"
      "explain"
      "list"
      "outdated"
      "run"
      "search"
      "test"
      "view"
    ];
    npx = null;

    # Jujutsu (read-only)
    jj = [
      "describe"
      "diff"
      "log"
      "show"
      "status"
      "workspace list"
      "workspace root"
    ];

    # systemctl (read-only)
    systemctl = [
      "cat"
      "is-active"
      "is-enabled"
      "list-dependencies"
      "list-timers"
      "list-unit-files"
      "list-units"
      "show"
      "status"
    ];
    journalctl = null;

    # Nix (read-only)
    nix = [
      "build"
      "derivation show"
      "eval"
      "flake"
      "hash"
      "path-info"
      "search"
      "store"
      "why-depends"
    ];
    nix-instantiate = [ "--eval" ];
    nix-store = [
      "--query"
      "-q"
    ];
    nix-prefetch-url = null;
    nix-hash = null;
    nixos-option = null;
  };

  # File system read access patterns
  readPaths = [
    "${config.home.homeDirectory}/.cargo"
    "/nix/store"
  ];

  # Web access
  web = {
    search = true;
    fetch = true;
    urls = [ "raw.githubusercontent.com" ];
  };

  # MCP tool permissions (none currently configured)
  mcpTools = [ ];

  # ── Formatters ─────────────────────────────────────────────────────────

  # Expand the commands map into a flat list using a formatting function
  expandCommands = formatFull: formatSub:
    lib.concatLists (lib.mapAttrsToList (cmd: subCmds:
      if subCmds == null then
        [ (formatFull cmd) ]
      else
        builtins.map (sub: formatSub cmd sub) subCmds
    ) commands);

  # Antigravity IDE: "command(cmd)" / "command(cmd sub)"
  antigravityCommands = expandCommands
    (cmd: "command(${cmd})")
    (cmd: sub: "command(${cmd} ${sub})");

  antigravityWeb = lib.concatMap (url: [ "read_url(${url})" ]) web.urls;

in
{
  lib.permissions = {
    # Tool-agnostic definitions, for renderers of other tools' formats.
    inherit
      commands
      readPaths
      web
      mcpTools
      expandCommands
      ;

    # Fully formatted permission lists
    forAntigravity =
      antigravityWeb
      ++ [ "command(cd)" ]
      ++ antigravityCommands;
  };
}
