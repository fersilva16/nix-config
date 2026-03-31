{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "ledger";
  system = {
    launchd.user.agents.ledger-sync = {
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
