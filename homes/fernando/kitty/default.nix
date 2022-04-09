{ ... }: {
  programs.kitty = {
    enable = true;

    font = { name = "Caskaydia Cove Nerd Font"; };

    theme = "Doom One";

    settings = {
      disable_ligatures = "never";
      cursor_shape = "beam";
    };
  };
}
