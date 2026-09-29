{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  version = "5.1.2";

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
      hash = "sha256-XhIoawigjoxlmYfHqhWYFsFygC6tEzUVHgz+PTXsV48=";
    };
    dontUnpack = true;
    # The bun payload is appended to the executable; stripping would drop it.
    dontStrip = true;
    # Byte-patching the payload invalidates the signature; the hook re-signs.
    nativeBuildInputs = [
      pkgs.perl
      pkgs.darwin.autoSignDarwinBinariesHook
    ];
    # On the Claude Agent SDK route, omo hands its tools to the model through
    # jsonSchemaToZodShape, which drops every property description. Nothing then
    # tells the model eval's `summary` is required, so eval runs fail with
    # "eval run requires summary" (still unfixed upstream as of v5.1.2). The patch
    # keeps descriptions and marks `summary` (only eval has one) required. It must
    # keep the same byte length because the bun payload is laid out by offset.
    patchFrom = "function jsonSchemaToZodShape(schema){const object=schema??{};const properties=object.properties??{};const required=new Set(object.required??[]);const shape={};for(const[key,value]of Object.entries(properties)){const converted=schemaToZod(value);shape[key]=required.has(key)?converted:converted.optional()}return shape}";
    patchTo = ''function jsonSchemaToZodShape(s){const o=s??{},r=new Set(o.required??[]),h={};for(const[k,v]of Object.entries(o.properties??{})){let c=schemaToZod(v);if(v.description)c=c.describe(v.description);h[k]=r.has(k)||k=="summary"?c:c.optional()}return h}'';
    installPhase = ''
      runHook preInstall
      install -Dm755 $src $out/bin/omo
      perl -0777 -pi -e '
        BEGIN { $f = $ENV{patchFrom}; $t = $ENV{patchTo}; $p = length($f) - length($t);
                die "omo patch: replacement too long\n" if $p < 0; substr($t, -1, 0) = " " x $p; }
        $n += s/\Q$f\E/$t/g;
        END { die "omo patch: jsonSchemaToZodShape not found, drop or update the patch\n" unless $n; }
      ' $out/bin/omo
      runHook postInstall
    '';
    meta = {
      platforms = [ "aarch64-darwin" ];
      mainProgram = "omo";
    };
  };

  # Agent PATH (dev/agent-path): tool calls, and the shared RPC host omo
  # spawns, see ~/.agents/bin first. The process still execs as `omo`, so
  # tmux's agent-commands match, window icon and resurrect are unaffected.
  omoWithAgentPath = pkgs.writeShellScriptBin "omo" ''
    export PATH="$HOME/.agents/bin:$PATH"
    exec -a omo ${omo}/bin/omo "$@"
  '';
in
mkUserModule {
  name = "omo";
  parts.agent = import ./agent/agent.nix { inherit pkgs lib; };
  home =
    { userCfg, ... }:
    {
      # omo warns at startup without it ("Pi works best with csi-u"); tmux
      # sends extended keys in xterm's format by default.
      programs.tmux.extraConfig = lib.mkIf userCfg.tmux.enable ''
        set -g extended-keys-format csi-u
      '';

      home = {
        packages = [ (if userCfg.agent-path.enable then omoWithAgentPath else omo) ];

        file = lib.mkMerge [
          # The opencode notifier's contract, published from omo's own events:
          # bar colour, session-picker glyph, prefix+N queue, sounds.
          (lib.mkIf userCfg.opencode-manager.enable {
            ".omo/agent/extensions/tmux-notifier.ts".source = ./tmux-notifier.ts;
          })
          # Flexoki light, matching ghostty/kitty/nvim/tmux/opencode.
          { ".omo/agent/themes/flexoki.json".source = ./flexoki.json; }
          # opencode-style prompt, status line, sidebar and tool blocks.
          { ".omo/agent/extensions/ui".source = ./ui; }
        ];

        # omo rewrites settings.json itself (tips history, model picks), so it
        # can't be a store symlink: merge the UI keys in on every activation.
        # opencode-like look: fullscreen, Flexoki, no startup header or tips.
        activation.omoSettings = {
          after = [ "writeBoundary" ];
          before = [ ];
          data = ''
            f="$HOME/.omo/agent/settings.json"
            mkdir -p "$(dirname "$f")"
            [ -s "$f" ] || echo '{}' > "$f"
            ${pkgs.jq}/bin/jq '. + {
              theme: "flexoki",
              tuiMode: "fullscreen",
              fullscreenExitOutput: "resume-hint",
              quietStartup: true,
              tips: false,
              collapseChangelog: true
            }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
          '';
        };
      };

      xdg.configFile = lib.mkMerge [
        (lib.mkIf userCfg.opencode-manager.enable {
          "tmux-opencode-manager/agent-commands".text = "^omo$";
        })
        # Appends to the `icons:` map cli/tmux/theme.nix writes, so it must
        # land after it. Glyph is U+F51B, chosen by hand: keep it.
        (lib.mkIf userCfg.tmux.enable {
          "tmux/tmux-nerd-font-window-name.yml".text = lib.mkAfter "  omo: \"\"";
        })
      ];
    };
}
