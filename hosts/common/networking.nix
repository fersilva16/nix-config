_:
{
  networking = {
    networkmanager.enable = true;
    useDHCP = false;

    interfaces.wlp0s20f3 = {
      useDHCP = true;
    };
  };

  networking.extraHosts = ''
    127.0.0.1 company1
    127.0.0.1 company2
    127.0.0.1 company3
    127.0.0.1 company4
    127.0.0.1 company5
  '';
}
