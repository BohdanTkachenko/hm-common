{ lib, stdenvNoCC, fetchFromGitHub, glib }:

# Search Light built from upstream master. nixpkgs/EGO still ship v42, whose
# metadata declares shell-version 48/49 only, so GNOME 50 disables it. Master
# (PR #154, "Add GNOME 50 support") declares 48/49/50 but has no tagged release
# yet — drop this override once nixpkgs' gnomeExtensions.search-light supports 50.
stdenvNoCC.mkDerivation {
  pname = "gnome-shell-extension-search-light";
  version = "101-unstable-2026-03-17";

  src = fetchFromGitHub {
    owner = "icedman";
    repo = "search-light";
    rev = "4e93e0e3e2fba8512dfd588177b7a6a2a71c9f1e";
    hash = "sha256-mUzmf2qWGM/aCidFFktFuOdY7e1QiB6MbvN2cOVg7Qs=";
  };

  nativeBuildInputs = [ glib ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    glib-compile-schemas --strict schemas
    runHook postBuild
  '';

  # Mirror the upstream Makefile `publish` target: copy the shipped file set,
  # then strip the untranspiled source JS that the released extension omits.
  installPhase = ''
    runHook preInstall
    ext=$out/share/gnome-shell/extensions/search-light@icedman.github.com
    mkdir -p "$ext"
    cp LICENSE metadata.json stylesheet.css README.md CHANGELOG.md "$ext/"
    cp *.js "$ext/"
    rm -f "$ext"/_*.js "$ext"/utils.js "$ext"/drawing.js "$ext"/chamfer.js "$ext"/imports_*.js
    cp -r ui preferences effects apps schemas "$ext/"
    runHook postInstall
  '';

  passthru.extensionUuid = "search-light@icedman.github.com";

  meta = {
    description = "Take the apps search out of overview (GNOME 50, from upstream master)";
    homepage = "https://github.com/icedman/search-light";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
