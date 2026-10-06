# Wrap a package so its executables auto-pin themselves to CCD1 (cores
# 8-15,24-31) on hosts that provide the `build-run` helper. On hosts without
# `build-run`, the wrapper is a no-op pass-through.
#
# Use for AI/build/background tooling that should never compete for the
# V-cache CCD0 (reserved for games and latency-sensitive workloads).
#
# Usage:
#   let pinToCCD1 = import ../../lib/pin-to-ccd1.nix { inherit pkgs; };
#   in pinToCCD1 pkgs.gemini-cli
{ pkgs }:
pkg:
# CCD pinning is a 9950X3D (x86) concern; on other arches (e.g. aarch64 cloud)
# the wrapper has nothing to pin to, so pass the package through unchanged.
# x86 hosts that aren't the X3D desktop still get wrapped here, but only the
# X3D hosts ship `build-run`, so the runtime `command -v` check above makes the
# wrapper inert everywhere else.
if !pkgs.stdenv.hostPlatform.isx86_64 then
  pkg
else
  let
    joined = pkgs.symlinkJoin {
    name = "${pkg.pname or pkg.name or "pkg"}-ccd1-pinned";
    paths = [ pkg ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    # Forward attrs that downstream modules (e.g. programs.vscode) read off the
    # package: pname, version, meta. symlinkJoin drops them by default.
    meta = pkg.meta or {};
    pname = pkg.pname or pkg.name or "pkg";
    version = pkg.version or "0";
    postBuild = ''
      for bin in $out/bin/*; do
        [ -e "$bin" ] && [ -x "$bin" ] || continue
        wrapProgram "$bin" \
          --run 'if command -v build-run >/dev/null 2>&1 && [ -z "''${_PINNED_CCD1:-}" ]; then export _PINNED_CCD1=1; exec build-run "$0" "$@"; fi'
      done
    '';
  };
in
joined
