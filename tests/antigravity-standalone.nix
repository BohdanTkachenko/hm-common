{ pkgs, home-manager }:
let
  # Exercise the real installer with a local release fixture: no network and
  # no writes outside the build sandbox.
  mockCurl = pkgs.writeShellScriptBin "curl" ''
    if [[ "''${AGY_TEST_FAIL_FETCH:-}" == 1 ]]; then
      echo "unexpected download during an idempotent install" >&2
      exit 1
    fi
    destination=""
    fixture=payload
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -o) destination="$2"; shift ;;
        https://*/manifests/*.json) fixture=manifest.json ;;
      esac
      shift
    done
    echo "$fixture" >> "$AGY_TEST_FIXTURES/calls"
    cp "$AGY_TEST_FIXTURES/$fixture" "$destination"
  '';
  home = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      (
        args:
        import ../home/programs/antigravity/standalone.nix (
          args
          // {
            pkgs = pkgs // {
              curl = mockCurl;
            };
          }
        )
      )
      ({ lib, ... }: {
        options.my.antigravity.cli.package = lib.mkOption { type = lib.types.package; };
        config = {
          home.username = "agy-test";
          home.homeDirectory = "/build/agy-home";
          home.stateVersion = "26.05";
          my.antigravity.cli.standalone.enable = true;
        };
      })
    ];
  };
  installer = builtins.head home.config.systemd.user.services.antigravity-cli-standalone-install.Service.ExecStart;
  launcher = home.config.home.file.".local/bin/agy".source;
in
pkgs.runCommand "antigravity-standalone-test"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnutar
      pkgs.gzip
      pkgs.jq
    ];
  }
  ''
    export AGY_TEST_FIXTURES="$TMPDIR/fixtures"
    mkdir -p "$AGY_TEST_FIXTURES" /build/agy-home/.local/share/antigravity-cli
    executable=/build/agy-home/.local/share/antigravity-cli/agy
    ln -s ${pkgs.hello}/bin/hello "$executable"

    printf '#!${pkgs.runtimeShell}\nprintf "%%s\\n" 9.9.9\n' > "$AGY_TEST_FIXTURES/antigravity"
    tar -czf "$AGY_TEST_FIXTURES/payload" -C "$AGY_TEST_FIXTURES" antigravity
    checksum=$(sha512sum "$AGY_TEST_FIXTURES/payload" | cut -d' ' -f1)
    manifest() {
      jq -n --arg checksum "$1" '{url: "https://example.invalid/agy.tar.gz", sha512: $checksum}' \
        > "$AGY_TEST_FIXTURES/manifest.json"
    }

    # A bad release must leave the existing executable untouched and clean up.
    manifest "$(printf '%0128d' 0)"
    if ${installer}; then
      echo "installer accepted a bad checksum" >&2
      exit 1
    fi
    test "$(readlink "$executable")" = ${pkgs.hello}/bin/hello
    test -z "$(find /build/agy-home/.local/share/antigravity-cli -name '.install.*' -print -quit)"

    # A verified release replaces the read-only symlink atomically. Both the
    # profile launcher and the ~/.local/bin link use this same writable binary.
    manifest "$checksum"
    ${installer}
    test ! -L "$executable"
    test -w "$executable"
    test "$(${launcher} --version)" = 9.9.9

    export AGY_TEST_FAIL_FETCH=1
    ${installer}
    test "$(wc -l < "$AGY_TEST_FIXTURES/calls")" = 4
    test -z "$(find /build/agy-home/.local/share/antigravity-cli -name '.install.*' -print -quit)"
    touch "$out"
  ''
