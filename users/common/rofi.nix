{ pkgs, config, ... }:
let
  inherit (config.lib.formats.rasi) mkLiteral;
  inherit (config) colors;
in
{
  programs.rofi = {
    enable = true;

    cycle = true;

    font = "Fira Code Medium Nerd Font Complete";

    plugins = with pkgs; [
      rofimoji
      rofi-calc
      rofi-power-menu
    ];

    terminal = "kitty";

    theme = {
      "*" = {
        selected-active-foreground = mkLiteral colors.bg;
        lightfg = mkLiteral colors.fg;
        separator-color = mkLiteral colors.fgAlt;
        urgent-foreground = mkLiteral colors.red;
        alternate-urgent-background = mkLiteral colors.blue;
        lightbg = mkLiteral colors.bg;
        background-color = mkLiteral colors.bgAlt;
        border-color = mkLiteral colors.cyan;
        normal-background = mkLiteral colors.bgAlt;
        selected-urgent-background = mkLiteral colors.orange;
        alternate-active-background = mkLiteral colors.magenta;
        # spacing = mkLiteral colors.;
        alternate-normal-foreground = mkLiteral colors.fgAlt;
        urgent-background = mkLiteral colors.bg;
        selected-normal-foreground = mkLiteral colors.fg;
        active-foreground = mkLiteral colors.fg;
        background = mkLiteral colors.bgAlt;
        selected-active-background = mkLiteral colors.bg;
        active-background = mkLiteral colors.bg;
        selected-normal-background = mkLiteral colors.bg;
        alternate-normal-background = mkLiteral colors.bg;
        foreground = mkLiteral colors.fg;
        selected-urgent-foreground = mkLiteral colors.orange;
        normal-foreground = mkLiteral colors.fg;
        alternate-urgent-foreground = mkLiteral colors.magenta;
        alternate-active-foreground = mkLiteral colors.magenta;
      };

      element = {
        padding = mkLiteral "1px";
        cursor = mkLiteral "pointer";
        spacing = mkLiteral "5px";
        border = 0;
      };

      "element normal.normal" = {
        background-color = mkLiteral "var(normal-background)";
        text-color = mkLiteral "var(normal-foreground)";
      };

      "element normal.urgent" = {
        background-color = mkLiteral "var(urgent-background)";
        text-color = mkLiteral "var(urgent-foreground)";
      };

      "element normal.active" = {
        background-color = mkLiteral "var(active-background)";
        text-color = mkLiteral "var(active-foreground)";
      };

      "element selected.normal" = {
        background-color = mkLiteral "var(selected-normal-background)";
        text-color = mkLiteral "var(selected-normal-foreground)";
      };

      "element selected.urgent" = {
        background-color = mkLiteral "var(selected-urgent-background)";
        text-color = mkLiteral "var(selected-urgent-foreground)";
      };

      "element selected.active" = {
        background-color = mkLiteral "var(selected-active-background)";
        text-color = mkLiteral "var(selected-active-foreground)";
      };

      "element alternate.normal" = {
        background-color = mkLiteral "var(alternate-normal-background)";
        text-color = mkLiteral "var(alternate-normal-foreground)";
      };

      "element alternate.urgent" = {
        background-color = mkLiteral "var(alternate-urgent-background)";
        text-color = mkLiteral "var(alternate-urgent-foreground)";
      };

      "element alternate.active" = {
        background-color = mkLiteral "var(alternate-active-background)";
        text-color = mkLiteral "var(alternate-active-foreground)";
      };

      element-text = {
        background-color = mkLiteral "transparent";
        cursor = mkLiteral "inherit";
        highlight = mkLiteral "inherit";
        text-color = mkLiteral "inherit";
      };

      element-icon = {
        background-color = mkLiteral "transparent";
        size = mkLiteral "2em";
        cursor = mkLiteral "inherit";
        text-color = mkLiteral "inherit";
      };

      window = {
        padding = 5;
        background-color = mkLiteral "var(background)";
        border = 2;
      };

      mainbox = {
        padding = 0;
        border = 0;
      };

      message = {
        padding = mkLiteral "1px";
        border-color = mkLiteral "var(separator-color)";
        border = mkLiteral "2px dash 0px 0px";
      };

      textbox = {
        text-color = mkLiteral "var(foreground)";
      };

      listview = {
        padding = mkLiteral "2px 0px 0px";
        scrollbar = true;
        border-color = mkLiteral "var(separator-color)";
        spacing = mkLiteral "2px";
        fixed-height = 0;
        border = mkLiteral "2px dash 0px 0px";
      };

      scrollbar = {
        width = mkLiteral "4px";
        padding = 0;
        handle-width = mkLiteral "8px";
        border = 0;
        handle-color = mkLiteral "var(normal-foreground)";
      };

      sidebar = {
        border-color = mkLiteral "var(separator-color)";
        border = mkLiteral "2px dash 0px 0px";
      };

      button = {
        cursor = mkLiteral "pointer";
        spacing = 0;
        text-color = mkLiteral "var(normal-foreground)";
      };

      "button selected" = {
        background-color = mkLiteral "var(selected-normal-background)";
        text-color = mkLiteral "var(selected-normal-foreground)";
      };

      num-filtered-rows = {
        expand = false;
        text-color = mkLiteral "Gray";
      };

      num-rows = {
        expand = false;
        text-color = mkLiteral "Gray";
      };

      textbox-num-sep = {
        expand = false;
        str = "/";
        text-color = mkLiteral "Gray";
      };

      inputbar = {
        padding = mkLiteral "1px";
        spacing = mkLiteral "0px";
        text-color = mkLiteral "var(normal-foreground)";
        children = mkLiteral "[ \"prompt\",\"textbox-prompt-colon\",\"entry\",\"num-filtered-rows\",\"textbox-num-sep\",\"num-rows\",\"case-indicator\" ]";
      };

      case-indicator = {
        spacing = 0;
        text-color = mkLiteral "var(normal-foreground)";
      };

      entry = {
        text-color = mkLiteral "var(normal-foreground)";
        cursor = mkLiteral "text";
        spacing = 0;
        placeholder-color = mkLiteral "Gray";
        placeholder = "Type to filter";
      };

      prompt = {
        spacing = 0;
        text-color = mkLiteral "var(normal-foreground)";
      };

      textbox-prompt-colon = {
        margin = mkLiteral "0px 1em 1em 1em";
        expand = false;
        str = ":";
        text-color = mkLiteral "inherit";
      };
    };

    extraConfig = {
      # modi = mkLiteral "[ window, run, ssh, drun ]";
      kb-row-up = "Up,Control+k,Shift+Tab,Shift+ISO_Left_Tab";
      kb-row-down = "Down,Control+j";
      kb-accept-entry = "Control+m,Return,KP_Enter";
      kb-remove-to-eol = "Control+Shift+e";
      # kb-mode-next = "Shift+Right,Control+Tab,Control+l";
      kb-mode-previous = "Shift+Left,Control+Shift+Tab,Control+h";
      kb-remove-char-back = "BackSpace";
    };
  };
}
