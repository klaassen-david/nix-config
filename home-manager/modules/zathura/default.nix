{
  config,
  pkgs,
  lib,
  ...
}:

let
  # zathura's comic-book reader (.cbz/.cbr/.cb7/.cbt) ships a MimeType= that also
  # claims the *generic* container types those comics happen to be built on:
  # application/zip, x-tar, x-rar, x-7z-compressed and even inode/directory. Since
  # nothing else registers for e.g. application/zip, zathura-cb becomes its default
  # handler — so plain zips, tarballs and directories all open in a comic reader.
  #
  # Worse for us: xlsx/docx/pptx are OOXML *subclasses of application/zip*. Many
  # servers serve them as application/zip, and Firefox/Zen launch a download by its
  # recorded MIME type (not the .xlsx extension), so they resolve to the zip default
  # (zathura-cb) and never reach the xlsx→calc mapping. Drop the over-broad claims;
  # the comic-specific types (x-cbz/x-cbr/…) still open in zathura.
  zathuraCb = "org.pwmt.zathura-cb.desktop";
  ungrabbedTypes = [
    "application/zip"
    "application/x-tar"
    "application/x-rar"
    "application/x-7z-compressed"
    "inode/directory"
  ];
in
{
  xdg.mimeApps.defaultApplications."application/pdf" = "org.pwmt.zathura-pdf-mupdf.desktop";

  xdg.mimeApps.associations.removed = lib.genAttrs ungrabbedTypes (_: zathuraCb);

  programs.zathura = {
    enable = true;
    # colours from stylix's zathura target; it sets no font, so stylix's
    # monospace at its application size is set here
    extraConfig = ''
      set synctex true
      set synctex-editor-command "texlab inverse-search -i %{input} -l %{line}"
      set selection-clipboard clipboard
      set font "${config.stylix.fonts.monospace.name} normal ${toString config.stylix.fonts.sizes.applications}"
      set recolor true
      set recolor-reverse-video "true"
      set recolor-keephue "true"
    '';
  };
}
