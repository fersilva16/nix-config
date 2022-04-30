let
  eDP-1-1 = "00ffffffffffff0030e4e40500000000001c0104a5221378eae085a3544e9b260e5054000000010101010101010101010101010101015e8780a070384d403020350058c21000001b000000000000000000000000000000000000000000fe0046524a5932803135365746470a000000000002413f9e001000000b010a20200080";
  HDMI-0 = "00ffffffffffff00410cb1c086cf00000917010380301b782a92c5a259559e270e5054bd4b00d1c08180950f9500b30081c001010101023a801871382d40582c4500dd0c1100001e000000ff0046583831333039303533313236000000fc005068696c697073203232365634000000fd00384c1e5311000a20202020202001f402031b6143908402230907078301000067030c0020008028e2000f8c0ad08a20e02d10103e9600a05a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002e";
in
_:
{
  programs.autorandr = {
    enable = true;

    profiles = {
      dual = {
        fingerprint = {
          inherit eDP-1-1 HDMI-0;
        };

        config = {
          eDP-1-1 = {
            enable = true;
            primary = true;
            position = "1920x0";
            mode = "1920x1080";
            rate = "144.0";
            dpi = 96;
          };

          HDMI-0 = {
            enable = true;
            position = "0x0";
            mode = "1920x1080";
            rate = "60.0";
            dpi = 96;
          };
        };
      };

      single = {
        fingerprint = {
          inherit eDP-1-1;
        };

        config = {
          eDP-1-1 = {
            enable = true;
            primary = true;
            position = "0x0";
            mode = "1920x1080";
            rate = "144.0";
            dpi = 96;
          };
        };
      };
    };
  };
}
