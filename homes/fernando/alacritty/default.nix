{ pkgs, ... }: {
  programs.alacritty = {
    enable = true;

    settings = {
      font = {
        normal = {
          family = "Caskaydia Cove Nerd Font";
          style = "Regular";
        };

        bold = {
          family = "Caskaydia Cove Nerd Font";
          style = "Bold";
        };

        italic = {
          family = "Caskaydia Cove Nerd Font";
          style = "Italic";
        };

        bold_italic = {
          family = "Caskaydia Cove Nerd Font";
          style = "Bold Italic";
        };
      };
    };
  };
}
