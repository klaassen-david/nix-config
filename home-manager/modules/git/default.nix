{ ... }:

{
  programs.git = {
    enable = true;
    signing.format = null;
    settings = {
      init.defaultBranchName = "main";
    };
    ignores = [
      "**/Session.vim"
      "**/*.swp"
      "**/.claude/"
    ];
  };
}
