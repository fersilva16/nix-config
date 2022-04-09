{ ... }: {
  boot = {
    loader = {
      timeout = 10;
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };

      # Using grub because of the dualboot with Windows
      # TODO: move it to another file
      grub = {
        enable = true;
        version = 2;

        efiSupport = true;

        devices = [ "nodev" ];

        extraEntries = ''
          menuentry "Windows" {
            insmod part_gpt
            insmod fat
            insmod search_fs_uuid
            insmod chain
            search --fs-uuid --set=root 3436-097E
            chainloader /EFI/Microsoft/Boot/bootmgfw.efi
          }
        '';
      };

      # systemd-boot = {
      #   enable = true;
      #   consoleMode = "max";
      #   editor = false;
      # };
    };
  };
}
