{ username, pkgs, ... }:
{
  home-manager.users.${username} = {
    home.packages = with pkgs; [ ledger ];
  };

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
}
