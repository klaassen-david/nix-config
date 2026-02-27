{ pkgs, lib, ... } :

{
  programs.zathura = {
    enable = true;
    extraConfig = ''
      set synctex true
      set synctex-editor-command "texlab inverse-search -i %{input} -l %{line}"
      set font "firacode normal 11"
      set default-bg "rgba(46, 52, 64, 0.8)"
      set recolor true
      set recolor-lightcolor "rgba(0, 0, 0, 0.1)"
      set recolor-reverse-video "true"
      set recolor-keephue "true"
    '';
  };
}
