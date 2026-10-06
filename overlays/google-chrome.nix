{
  config,
  lib,
  pkgs,
  ...
}:
let
  # https://chromium.googlesource.com/chromium/src/+/lkgr/docs/gpu/vaapi.md#vaapi-on-linux
  vaapiEnableFeatures = [
    # An AcceleratedVideoEncoder (AVE) performs high-level, platform-independent
    # encoding process tasks, such as managing codec state, reference frames,
    # etc., but may require support from an external accelerator (typically a
    # hardware accelerator) to offload some stages of the actual encoding
    # process, using the parameters that AVE prepares beforehand.
    "AcceleratedVideoEncoder"

    # The following feature can improve performance when using EGL/Wayland.
    # It is enabled by default, but keeping this just in case.
    "AcceleratedVideoDecodeLinuxZeroCopyGL"

    ## Vulkan

    # Enable Vulkan graphics backend for compositing and rasterization.
    "Vulkan"

    # Use ANGLE's Vulkan backend.
    "DefaultANGLEVulkan"

    # Enable sharing Vulkan device queue with ANGLE's Vulkan backend.
    "VulkanFromANGLE"

    # Enable skipping the Vulkan blocklist.
    #"SkipVulkanBlocklist"

    # Ignore the non-intel driver blacklist for VaapiVideoDecoder
    # implementations.
    "VaapiIgnoreDriverChecks"

    # Enables the use of VA-API for hardware-accelerated video decoding.
    "VaapiVideoDecoder"

    # Enables the use of VA-API for hardware-accelerated video encoding.
    "VaapiVideoEncoder"

    # Enables hardware-accelerated decoding specifically for WebRTC (video calls).
    "WebRtcHWDecoding"

    # Enables hardware-accelerated encoding specifically for WebRTC.
    "WebRtcHWEncoding"

    # Enables hardware-accelerated VP8 encoding for WebRTC.
    "WebRtcHWVP8Encoding"

    # Enables hardware-accelerated VP9 encoding for WebRTC.
    "WebRtcHWVP9Encoding"

    # Generic flag to enable hardware-accelerated video decoding across the browser.
    "AcceleratedVideoDecoder"
  ];
  vaapiFlags = [
    ## Vulkan
    "--use-gl=angle"
    "--use-angle=vulkan"

    # Optional
    # "--ignore-gpu-blocklist"
    # "--disable-gpu-driver-bug-workaround"
  ];

  # Enable Gemini Live in Chrome.
  geminiFeatures = [
    "ContextualCueing"
    "Glic"
    "GlicDevelopmentCookies"
    "GlicKeyboardShortcutNewBadge"
    "GlicRollout"
    "TabstripComboButton"
  ];

  disableFeatures = [
    # Prevent Chrome from capturing hardware media keys (Playy/Pause/etc).
    "HardwareMediaKeyHandling"
  ];

  enableFeatures =
    vaapiEnableFeatures
    ++ geminiFeatures
    ++ [
      # Use dark mode for Chrome internal views.
      "WebUIDarkMode"

      # Enable Gemini in Chrome.
      "ContextualCueing"
    ];

  allFlags = vaapiFlags ++ [
    # Pin the cookie/password encryption backend to the GNOME keyring
    # (libsecret). Chrome otherwise auto-detects the backend once at launch,
    # and on a slow/racy login it can fall back to the "basic" store (a
    # hardcoded key). That fallback can't decrypt keyring-encrypted (v11)
    # cookies, which silently logs out every site. Pinning it keeps the
    # backend deterministic across updates and reboots.
    "--password-store=gnome-libsecret"

    # Ignore theme reported by OS and use dark mode.
    # TIn certain cases there are issues with GNOME reporting theme correctly.
    "--force-dark-mode"

    # Prevent using RAM to draw web pages. Use graphics card memory instead.
    "--enable-zero-copy"

    # Make scrolling smooth.
    "--enable-smooth-scrolling"

    # Enable GTK4.
    "--gtk-version=4"

    ("--disable-features=" + (builtins.concatStringsSep "," disableFeatures))
    ("--enable-features=" + (builtins.concatStringsSep "," enableFeatures))
  ];
in
{
  nixpkgs.overlays = [
    (final: prev: {
      google-chrome = config.my.google-chrome.mkWrapper prev.google-chrome allFlags;
    })
  ];
}
