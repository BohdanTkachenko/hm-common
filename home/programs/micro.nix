{
  home.sessionVariables.EDITOR = "micro";
  home.sessionVariables.VISUAL = "micro";

  programs.micro = {
    enable = true;
    settings = {
      autoindent = true;
      colorscheme = "monokai";
      mkparents = true;
      scrollbar = true;
      softwrap = true;
      tabsize = 2;
      tabstospaces = true;
      wordwrap = true;
    };
  };
}
