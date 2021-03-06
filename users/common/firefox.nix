{ pkgs, ... }:
{
  programs.firefox = {
    enable = true;

    extensions = with pkgs.nur.repos.rycee.firefox-addons; [ ublock-origin ];

    profiles = {
      default = {
        settings = {
          "app.update.auto" = false;
        };
      };
    };
  };
}
