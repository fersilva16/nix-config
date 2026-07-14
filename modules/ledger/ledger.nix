{
  mkUserModule,
  pkgs,
  forPlatform,
  ...
}:
mkUserModule {
  name = "ledger";
  # launchd is darwin-only; systemd timer port deferred until wanted on linux.
  system = forPlatform {
    darwin.launchd.user.agents.ledger-sync = {
      command = ./ledger-sync.sh;

      serviceConfig = {
        RunAtLoad = false;

        StartCalendarInterval = [
          {
            Hour = 12;
            Minute = 0;
          }
        ];
      };
    };
  };
  home = {
    home.packages = with pkgs; [ ledger ];
  };
}
