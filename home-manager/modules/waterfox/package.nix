# Unwrapped Waterfox from the official Linux tarball, built like nixpkgs'
# firefox-bin (the shape wrapFirefox expects). Not in nixpkgs.
#
# Update: bump `version`, then
#   nix-prefetch-url https://cdn1.waterfox.net/waterfox/releases/<v>/Linux_x86_64/waterfox-<v>.tar.bz2
#   nix hash convert --hash-algo sha256 --to sri <hash>
# and re-check window.cfg against the new release: it patches browser internals.
#
# No policies.json / autoconfig here: the wrapper writes both (from
# programs.waterfox.policies and extraPrefsFiles) and would otherwise try to
# overwrite store symlinks.
{
  lib,
  stdenv,
  fetchurl,
  wrapGAppsHook3,
  autoPatchelfHook,
  patchelfUnstable,
  alsa-lib,
  curl,
  dbus-glib,
  gtk3,
  libxtst,
  libva,
  pciutils,
  pipewire,
  adwaita-icon-theme,
}:

stdenv.mkDerivation rec {
  pname = "waterfox-bin-unwrapped";
  version = "6.7.7";

  src = fetchurl {
    url = "https://cdn1.waterfox.net/waterfox/releases/${version}/Linux_x86_64/waterfox-${version}.tar.bz2";
    hash = "sha256-8KHGIAEU2lMJi78twSc60dnuvg2s5MLtM7eFsZlzLWA=";
  };

  nativeBuildInputs = [
    wrapGAppsHook3
    autoPatchelfHook
    # libxul.so carries a PROGBITS .relr.dyn (relrhack); plain patchelf breaks it
    patchelfUnstable
  ];
  buildInputs = [
    gtk3
    adwaita-icon-theme
    alsa-lib
    dbus-glib
    libxtst
  ];
  runtimeDependencies = [
    curl
    pciutils
    libva.out
  ];
  appendRunpaths = [ "${pipewire}/lib" ];
  patchelfFlags = [ "--no-clobber-old-sections" ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/waterfox-bin-${version}" "$out/bin"
    cp -r * "$out/lib/waterfox-bin-${version}"
    # updates come from nix (DisableAppUpdate is set by policy as well)
    rm -rf "$out/lib/waterfox-bin-${version}"/{updater,updater.ini,update-settings.ini,updates}
    ln -s "$out/lib/waterfox-bin-${version}/waterfox" "$out/bin/waterfox"
    runHook postInstall
  '';

  passthru = {
    applicationName = "Waterfox";
    binaryName = "waterfox";
    libName = "waterfox-bin-${version}";
    withFFmpeg = true;
    withGSSAPI = true;
    inherit gtk3;
  };

  meta = {
    description = "Waterfox, a Firefox ESR fork with native tree tabs (binary package)";
    homepage = "https://www.waterfox.com/";
    changelog = "https://github.com/BrowserWorks/Waterfox/releases/tag/${version}";
    license = lib.licenses.mpl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "waterfox";
  };
}
