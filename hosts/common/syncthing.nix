_:
{
  services.syncthing = {
    enable = true;
    openDefaultPorts = true;
    systemService = true;
    user = "fernando";
    group = "wheel";
    dataDir = "/home/fernando";

    devices = {
      iphone = {
        id = "NTSAZOC-WWYSD43-K3KRQXL-LRELC4O-RWXDPVT-PHBBWMX-4KCTUV3-EEDZTA3";
        name = "iPhone";
      };
    };

    folders = {
      org = {
        enable = true;
        id = "org";
        path = "/home/fernando/org";
        devices = [
          "iphone"
        ];
      };
    };
  };
}
