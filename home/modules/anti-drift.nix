{ config, lib, pkgs, ... }:
let
  cfg = config.anti-drift;

  jq = lib.getExe pkgs.jq;
  diff = lib.getExe' pkgs.diffutils "diff";

  fileEntries = lib.attrsToList cfg.files;

  # .gemini/settings.json → .gemini--settings.json.diff
  flatDriftName = path:
    (builtins.replaceStrings [ "/" ] [ "--" ] path) + ".diff";

  perFileScript = lib.concatMapStringsSep "\n" (entry:
    let
      path = entry.name;
      opts = entry.value;
      target = "$HOME/${path}";
      baseline = "${target}.nix-baseline";
      driftFile = "${cfg.driftDir}/${flatDriftName path}";
      jqDelPaths = lib.concatMapStringsSep ", " (p: if lib.hasPrefix "." p then p else ".${p}") opts.preserve;
      jqMergePaths = lib.concatMapStringsSep " | " (p:
        let pathStr = if lib.hasPrefix "." p then p else ".${p}";
        in "if ($target${pathStr} != null) then ${pathStr} = $target${pathStr} else . end"
      ) opts.preserve;
      normalize = if opts.json then
        if opts.preserve != [ ] then
          ''$jq --sort-keys 'del(${jqDelPaths})' "$1" 2>/dev/null || cat "$1"''
        else
          ''$jq --sort-keys . "$1" 2>/dev/null || cat "$1"''
      else
        ''cat "$1"'';
    in ''
      normalize_${builtins.replaceStrings [ "." "-" "/" " " ] [ "_" "_" "_" "_" ] path}() {
        ${normalize}
      }

      run mkdir -p "$(dirname "${target}")"

      # --- ${path} ---
      noteEcho "Processing ${target}"

      # Check for existing drift file
      if [ -f "${driftFile}" ]; then
        unresolvedDriftFiles+=("${driftFile}")
      fi

      # Detect drift
      if [ -f "${target}" ] && [ -e "${baseline}" ]; then
        normalizedBaseline=$(normalize_${builtins.replaceStrings [ "." "-" "/" " " ] [ "_" "_" "_" "_" ] path} "${baseline}")
        normalizedCurrent=$(normalize_${builtins.replaceStrings [ "." "-" "/" " " ] [ "_" "_" "_" "_" ] path} "${target}")

        if [ "$normalizedBaseline" != "$normalizedCurrent" ]; then
          # Save drift diff to repo
          run mkdir -p "${cfg.driftDir}"
          $diff -u \
            <(echo "$normalizedBaseline") \
            <(echo "$normalizedCurrent") \
            --label "nix-managed" --label "current" \
            > "${driftFile}" || true
          unresolvedDriftFiles+=("${driftFile}")

          noteEcho "anti-drift: drift detected in ~/${path}"
          cat "${driftFile}" >&2
        fi
      fi

      # Copy new version and update baseline
      ${if opts.json && opts.preserve != [ ] then ''
        if [ -f "${target}" ]; then
          $jq --argfile target "${target}" '${jqMergePaths}' "${opts.source}" > "${target}.tmp" 2>/dev/null || run cp "${opts.source}" "${target}.tmp"
        else
          run cp "${opts.source}" "${target}.tmp"
        fi
      '' else ''
        run cp "${opts.source}" "${target}.tmp"
      ''}
      run rm -f "${target}" "${baseline}"
      run mv "${target}.tmp" "${target}"
      run chmod 644 "${target}"
      # A copy, not a symlink: the source may be a mutable path (secret-manager
      # templates live at a fixed location that setupSops rewrites before this
      # runs), and a symlink to that resolves to the *new* content at the next
      # comparison — so every template change reads as user drift. A copy is a
      # true snapshot of what was last installed, whatever the source is.
      run cp "${opts.source}" "${baseline}"
    ''
  ) fileEntries;
in
{
  options.anti-drift.driftDir = lib.mkOption {
    type = lib.types.str;
    description = "Directory to store drift files (should be inside your config repo)";
  };

  options.anti-drift.files = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        source = lib.mkOption {
          type = with lib.types; either path str;
          description = "Nix store path or absolute path to copy from";
        };
        json = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Normalize with jq --sort-keys before diffing";
        };
        preserve = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "JSON keys/paths to preserve from the existing file and ignore during drift detection (only applicable when json = true)";
        };
      };
    });
    default = { };
    description = "Files to manage with mutable copy and drift detection";
  };

  config = lib.mkIf (cfg.files != { }) {
    home.file = lib.mapAttrs' (path: _opts:
      lib.nameValuePair path { enable = false; }
    ) cfg.files;

    home.activation.antiDrift = lib.hm.dag.entryAfter [ "reloadSystemd" "setupSops" ] ''
      jq="${jq}"
      diff="${diff}"

      unresolvedDriftFiles=()

      ${perFileScript}

      if [ ''${#unresolvedDriftFiles[@]} -gt 0 ]; then
        noteEcho ""
        noteEcho "anti-drift: unresolved drift files found:"
        for f in "''${unresolvedDriftFiles[@]}"; do
          noteEcho "  $f"
        done
        noteEcho ""
        noteEcho "Review and delete these files, then rebuild."
        exit 1
      fi
    '';
  };
}
