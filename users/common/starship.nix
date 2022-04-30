_:
{
  programs.starship = {
    enable = true;

    settings = {
      character = {
        success_symbol = "[λ](bold green)";
        error_symbol = "[λ](bold red)";
        vicmd_symbol = "[λ](bold blue)";
      };

      nix_shell = {
        format = "via [$symbol]($style) ";
        symbol = " ";
      };
    };
  };
}
