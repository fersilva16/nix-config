{ ... }:
{
  boot = {
    loader = {
      timeout = 10;
      efi.canTouchEfiVariables = true;

      systemd-boot = {
        enable = true;
        consoleMode = "max";
        editor = false;
      };
    };
  };
}
