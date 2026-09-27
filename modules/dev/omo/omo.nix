{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  version = "5.0.0";

  # OmO Native: the standalone `omo` (senpi engine + OMO extension), not the
  # opencode plugin in opencode/omo.nix. The release binary is bun-compiled and
  # self-contained; on first run it unpacks its runtime into
  # ~/.omo/binary-runtime/<version>/. `omo update` only prints a curl line on
  # a binary install, so bumping `version` here is the update path.
  omo = pkgs.stdenvNoCC.mkDerivation {
    pname = "omo";
    inherit version;
    src = pkgs.fetchurl {
      url = "https://github.com/code-yeongyu/oh-my-openagent/releases/download/v${version}/omo-darwin-arm64";
      hash = "sha256-W5MMs+6YDGn4N2ryFnkBXBxI3VV+6wGtkVnWfv/o0as=";
    };
    dontUnpack = true;
    # The bun payload is appended to the executable; stripping would drop it.
    dontStrip = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 $src $out/bin/omo
      runHook postInstall
    '';
    meta = {
      platforms = [ "aarch64-darwin" ];
      mainProgram = "omo";
    };
  };
in
mkUserModule {
  name = "omo";
  home =
    { userCfg, ... }:
    {
      home.packages = [ omo ];
      # omo warns at startup without it ("Pi works best with csi-u"); tmux
      # sends extended keys in xterm's format by default.
      programs.tmux.extraConfig = lib.mkIf userCfg.tmux.enable ''
        set -g extended-keys-format csi-u
      '';

      # The opencode notifier's contract, published from omo's own events:
      # bar colour, session-picker glyph, prefix+N queue, sounds.
      home.file = lib.mkIf userCfg.opencode-manager.enable {
        ".omo/agent/extensions/tmux-notifier.ts".source = ./tmux-notifier.ts;
      };

      xdg.configFile = lib.mkMerge [
        (lib.mkIf userCfg.opencode-manager.enable {
          "tmux-opencode-manager/agent-commands".text = "^omo$";
        })
        # Appends to the `icons:` map cli/tmux/theme.nix writes, so it must
        # land after it. md-creation (U+F0674).
        (lib.mkIf userCfg.tmux.enable {
          "tmux/tmux-nerd-font-window-name.yml".text = lib.mkAfter "  omo: \"󰙴\"";
        })
      ];
    };
}
