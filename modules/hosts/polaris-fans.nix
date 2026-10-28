# Case fans follow RAM temperature, not just CPU.
#
# The BIOS curve only follows the CPU. With the AIO keeping the CPU cool, the
# case fans idled at ~31% under full GPU+RAM load and the DIMMs reached 55C
# (4800 at 1.35V threw a memtest error near 62C). At 100% they held 42C.
#
# fan2go drives the case headers on the NCT6799 in two groups. The radiator
# fans go full speed for the CPU, the front, side and rear fans for the
# hottest DIMM, and each group runs at up to ~60% for the other group's heat,
# so a CPU-only or RAM-only load doesn't rev every fan. Header 7 (AIO pump)
# and the empty header 1 stay on the BIOS curve; on exit fan2go restores each
# header's original mode.
{ pkgs, ... }:
let
  # Mapped by spinning each header up alone.
  fans = [
    {
      id = "aio-top"; # CHA_FAN1: 3x radiator exhaust
      header = 2;
      curve = "aio";
    }
    {
      id = "front"; # CHA_FAN2: 3x intake
      header = 3;
      curve = "case";
    }
    {
      id = "side"; # CHA_FAN3: 3x intake
      header = 4;
      curve = "case";
    }
    {
      id = "rear"; # CHA_FAN4: 1x exhaust
      header = 6;
      curve = "case";
    }
  ];
  dimms = [
    "50"
    "51"
    "52"
    "53"
  ];
  # BIOS idle speed (~31%, ~600 rpm): idle stays as quiet as before.
  minPwm = 80;
  # ~60%: the ceiling a group runs at for the other group's heat.
  softMax = 155;

  # Tctl blips up to ~64C for a second under light load, and the fans follow
  # the curve directly: a 50-85C ramp in 5C stairs, held until the CPU is 5C
  # below a stair, so the fans don't surge.
  cpuStairs = id: top: {
    inherit id;
    staircase = {
      sensor = "cpu";
      hysteresis.down = 5;
      steps = builtins.genList (i: {
        "${toString (50 + 5 * i)}" = minPwm + (top - minPwm) * i / 7;
      }) 8;
    };
  };
  # Full speed by 50C keeps the DIMMs under their 55C warning flag.
  dimmLinear = top: d: {
    id = "dimm${d}-${toString top}";
    linear = {
      sensor = "dimm${d}";
      steps = [
        { "40" = minPwm; }
        { "50" = top; }
      ];
    };
  };
  maximum = id: curves: {
    inherit id;
    function = {
      type = "maximum";
      inherit curves;
    };
  };
  dimmCurves = top: map (d: "dimm${d}-${toString top}") dimms;

  settings = {
    dbPath = "/var/lib/fan2go/fan2go.db";
    fans = map (f: {
      inherit (f) id curve;
      hwmon = {
        platform = "nct6799-isa-0290";
        rpmChannel = f.header;
        pwmChannel = f.header;
      };
      neverStop = true;
      inherit minPwm;
      startPwm = minPwm;
      maxPwm = 255;
      useUnscaledCurveValues = true;
      pwmMap = "identity";
      setPwmToGetPwmMap = "identity";
      # The default PID took ~12s to reach the curve on a load step; the CPU
      # peaks within 3s anyway, so apply the curve value immediately.
      controlAlgorithm = "direct";
    }) fans;
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
      (cpuStairs "cpu" 255)
      (cpuStairs "cpu-soft" softMax)
    ]
    ++ map (dimmLinear 255) dimms
    ++ map (dimmLinear softMax) dimms
    ++ [
      (maximum "aio" ([ "cpu" ] ++ dimmCurves softMax))
      (maximum "case" ([ "cpu-soft" ] ++ dimmCurves 255))
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
