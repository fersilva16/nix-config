_:
{
  services.dunst = {
    enable = true;

    settings = {
      global = {
        monitor = 0;
        follow = "mouse";
        width = 320;
        height = 320;
        origin = "bottom-right";
        offset = "15x15";
        scale = 0;
        notification_limit = 0;
        progress_bar = false;
        indicate_hidden = "yes";
        transparency = 0;
        separator_height = 2;
        padding = 10;
        horizontal_padding = 10;
        text_icon_padding = 0;
        frame_width = 1;
        frame_color = "#333333";
        separator_color = "frame";
        sort = "yes";
        idle_threshold = 120;
        font = "Noto Sans 11";
        line_height = 0;
        markup = "full";
        format = "<span foreground='#f3f4f5'><b>%s %p</b></span>\n%b";
        alignment = "left";
        vertical_alignment = "center";
        show_age_threshold = 60;
        ellipsize = "middle";
        ignore_newline = "no";
        stack_duplicates = true;
        hide_duplicate_count = false;
        show_indicators = "yes";
        icon_position = "left";
        max_icon_size = 32;
        # icon_path = /usr/share/icons/Papirus-Dark/48x48/apps:/usr/share/icons/Papirus-Dark/48x48/categories:/usr/share/icons/Papirus-Dark/48x48/devices:/usr/share/icons/Papirus-Dark/48x48/emblems:/usr/share/icons/Papirus-Dark/48x48/mimetypes:/usr/share/icons/Papirus-Dark/48x48/places:/usr/share/icons/Papirus-Dark/48x48/status
        sticky_history = "yes";
        history_length = 20;
        always_run_script = true;
        corner_radius = 0;
        ignore_dbusclose = false;
        force_xinerama = false;
        mouse_left_click = "close_current";
        mouse_middle_click = "do_action, close_current";
        mouse_right_click = "close_all";
      };

      urgency_low = {
        background = "#333333";
        foreground = "#a8a8a8";
        timeout = 10;
      };

      urgency_normal = {
        background = "#333333";
        foreground = "#a8a8a8";
        timeout = 10;
      };

      urgency_critical = {
        background = "#d64e4e";
        foreground = "#f0e0e0";
        frame_color = "#d64e4e";
        timeout = 0;
      };
    };
  };
}
