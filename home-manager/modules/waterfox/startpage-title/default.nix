# Unsigned WebExtension: Startpage result pages are titled with the search
# string (title.js). Installed like the theme add-on
# (common/modules/theme/mozilla-theme.nix): Waterfox takes unsigned add-ons.
#
# The content hash is part of the id: an installed add-on is only replaced when
# its version goes up, so a changed script becomes a new add-on (the previous
# one stays installed, disabled).
{
  runCommand,
  writeText,
  zip,
}:

let
  hash = builtins.substring 0 12 (builtins.hashFile "sha256" ./title.js);
  addonId = "startpage-title-${hash}@nix-config";
  manifest = writeText "manifest.json" (
    builtins.toJSON {
      manifest_version = 2;
      name = "Startpage: search string as title (${hash})";
      version = "1.0";
      browser_specific_settings.gecko.id = addonId;
      content_scripts = [
        {
          matches = [
            "https://*.startpage.com/sp/search*"
            "https://*.startpage.com/do/*"
          ];
          js = [ "title.js" ];
          run_at = "document_end";
        }
      ];
    }
  );
in
runCommand "waterfox-startpage-title-${hash}"
  {
    nativeBuildInputs = [ zip ];
    passthru = { inherit addonId; };
  }
  ''
    dir="$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}"
    mkdir -p "$dir" build
    cp ${manifest} build/manifest.json
    cp ${./title.js} build/title.js
    (cd build && zip -qX "$dir/${addonId}.xpi" manifest.json title.js)
  ''
