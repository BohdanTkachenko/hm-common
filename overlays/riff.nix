{
  lib,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  cargo,
  rustc,
  meson,
  ninja,
  pkg-config,
  wrapGAppsHook4,
  blueprint-compiler,
  desktop-file-utils,
  gettext,
  glib,
  gtk4,
  libadwaita,
  openssl,
  alsa-lib,
  libpulseaudio,
}:
stdenv.mkDerivation rec {
  pname = "riff";
  # Upstream tags releases by number (v8); the version is the app's own.
  version = "26.07.1";

  src = fetchFromGitHub {
    owner = "Diegovsky";
    repo = "riff";
    tag = "v8";
    hash = "sha256-LblZ6/Oo/L86a+LzBR8r3rTaySPbRgyM+F+ClkMyXqY=";
  };

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit pname version src;
    hash = "sha256-2TNWubnoyFWkM48C2/mf02y6xvbwcAZjtCJRelsbY9w=";
  };

  postPatch = ''
    substituteInPlace src/meson.build --replace-fail \
      "cargo_output = 'src' / rust_target / meson.project_name()" \
      "cargo_output = 'src' / '${stdenv.hostPlatform.rust.cargoShortTarget}' / rust_target / meson.project_name()"
  '';

  nativeBuildInputs = [
    blueprint-compiler
    cargo
    desktop-file-utils
    gettext
    glib
    gtk4
    meson
    ninja
    pkg-config
    rustPlatform.cargoSetupHook
    rustc
    wrapGAppsHook4
  ];

  buildInputs = [
    alsa-lib
    glib
    gtk4
    libadwaita
    libpulseaudio
    openssl
  ];

  mesonBuildType = "release";
  mesonFlags = [ "-Doffline=true" ];
  env.CARGO_BUILD_TARGET = stdenv.hostPlatform.rust.rustcTargetSpec;

  meta = {
    description = "Native Spotify client for the GNOME desktop (fork of Spot)";
    homepage = "https://github.com/Diegovsky/riff";
    license = lib.licenses.mit;
    mainProgram = "riff";
    platforms = lib.platforms.linux;
  };
}
