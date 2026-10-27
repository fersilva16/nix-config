# Case fans follow RAM temperature, not just CPU.
#
# The BIOS curve only follows the CPU. With the AIO keeping the CPU cool, the
# case fans idled at ~31% under full GPU+RAM load and the DIMMs reached 55C
# (4800 at 1.35V threw a memtest error near 62C). At 100% they held 42C.
#
# fan2go runs every case header (2, 3, 4, 6 on the NCT6799) at the higher of a
# CPU curve and a hottest-DIMM curve, so whichever header the radiator fans sit
# on still tracks the CPU. Header 7 (AIO pump) and the empty header 1 stay on
# the BIOS curve; on exit fan2go restores each header's original mode.
{ pkgs, ... }:
let
  caseHeaders = [
    2
    3
    4
    6
  ];
  dimms = [
    "50"
    "51"
    "52"
    "53"
  ];
  # BIOS idle speed (~31%, ~600 rpm): idle stays as quiet as before.
  minPwm = 80;

  linear = sensor: steps: {
    id = sensor;
    linear = { inherit sensor steps; };
  };

  settings = {
    dbPath = "/var/lib/fan2go/fan2go.db";
    fans = map (h: {
      id = "case${toString h}";
      hwmon = {
        platform = "nct6799-isa-0290";
        rpmChannel = h;
        pwmChannel = h;
      };
      neverStop = true;
      inherit minPwm;
      startPwm = minPwm;
      maxPwm = 255;
      useUnscaledCurveValues = true;
      pwmMap = "identity";
      setPwmToGetPwmMap = "identity";
      curve = "case";
    }) caseHeaders;
    sensors = [
      {
        id = "cpu";
        hwmon = {
          platform = "k10temp-pci-00c3";
          channel = 1;
        };
      }
    ]
    ++ map (d: {
      id = "dimm${d}";
      hwmon = {
        platform = "spd5118-i2c-1-${d}";
        channel = 1;
      };
    }) dimms;
    curves = [
      (linear "cpu" [
        { "50" = minPwm; }
        { "85" = 255; }
      ])
    ]
    # Full speed by 50C keeps the DIMMs under their 55C warning flag.
    ++ map (
      d:
      linear "dimm${d}" [
        { "40" = minPwm; }
        { "50" = 255; }
      ]
    ) dimms
    ++ [
      {
        id = "case";
        function = {
          type = "maximum";
          curves = [ "cpu" ] ++ map (d: "dimm${d}") dimms;
        };
      }
    ];
  };
  configFile = (pkgs.formats.yaml { }).generate "fan2go.yaml" settings;
in
{
  boot.kernelModules = [ "nct6775" ];

  systemd.services.fan2go = {
    description = "fan2go fan control";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.fan2go}/bin/fan2go -c ${configFile} --no-style";
      Restart = "always";
      RestartSec = 10;
      StateDirectory = "fan2go";
    };
  };
}
