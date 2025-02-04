{ pkgs, ... }: {
  environment.etc = {
    "sysctl.conf" = {
      enable = true;
      text = ''
        kern.maxfiles=131072
        kern.maxfilesperproc=65536
      '';
    };
  };
}
