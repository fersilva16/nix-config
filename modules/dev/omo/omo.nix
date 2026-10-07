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
    # keeps descriptions and marks `summary` (only eval has one) required.
    zodFrom = "function jsonSchemaToZodShape(schema){const object=schema??{};const properties=object.properties??{};const required=new Set(object.required??[]);const shape={};for(const[key,value]of Object.entries(properties)){const converted=schemaToZod(value);shape[key]=required.has(key)?converted:converted.optional()}return shape}";
    zodTo = ''function jsonSchemaToZodShape(s){const o=s??{},r=new Set(o.required??[]),h={};for(const[k,v]of Object.entries(o.properties??{})){let c=schemaToZod(v);if(v.description)c=c.describe(v.description);h[k]=r.has(k)||k=="summary"?c:c.optional()}return h}'';
    # With showHardwareCursor on, the editor emits its cursor marker inside the
    # text only where it also draws the fake block, so the cursor vanishes as
    # soon as it leaves the end of the line. Always laying out the block keeps
    # the marker; the renderer strips the block again when the hardware cursor
    # is shown (extractCursorPosition).
    cursorFrom = "cursorInText&&cursor.drawFakeCursor?{";
    cursorTo = "cursorInText?{";
    # Every replacement is padded to the same byte length, because the bun
    # payload is laid out by offset.
    installPhase = ''
      runHook preInstall
      install -Dm755 $src $out/bin/omo
      bytePatch() {
        name="$1" from="$2" to="$3" perl -0777 -pi -e '
          BEGIN { $f = $ENV{from}; $t = $ENV{to}; $p = length($f) - length($t);
                  die "omo patch $ENV{name}: replacement too long\n" if $p < 0; substr($t, -1, 0) = " " x $p; }
          $n += s/\Q$f\E/$t/g;
          END { die "omo patch $ENV{name}: target not found, drop or update the patch\n" unless $n; }
        ' $out/bin/omo
      }
      bytePatch zod "$zodFrom" "$zodTo"
      bytePatch cursor "$cursorFrom" "$cursorTo"
      runHook postInstall
    '';
    meta = {
      platforms = [ "aarch64-darwin" ];
      mainProgram = "omo";
    };
  };

  # Footer status row: keep it subtle and compact. The OMO extension posts two
  # entries there with no config switch (as of v5.1.2): the
  # "(😺 OmO Native by Q Kim)" badge on every turn, and a 320 ms
  # "⚡ ultraworking..." spinner while a goal is active. The badge's handlers
  # are dropped, and the spinner becomes a dot that pulses between "•" and
  # "·" beside the word "goal" every 1.2 s.
  #
  # omo loads the extension from its unpacked runtime, not from the binary,
  # and the binary's embedded copy is sha256-checked whenever it unpacks, so
  # the patch targets the unpacked plugin/extensions/omo.js.
  footerPatches = [
    {
      name = "badge";
      from = ''r.publish(t)};t.on("session_start",i),t.on("agent_settled",i)}}}'';
      to = "r.publish(t)}/* nix: badge off */}}}";
    }
    {
      name = "goal-frames";
      from = ''oce=[`⚡ ultraworking''${"⠀".repeat(3)}`,`⚡ ultraworking.''${"⠀".repeat(2)}`,"⚡ ultraworking..⠀","⚡ ultraworking..."]'';
      to = ''oce=["• goal","· goal"]'';
    }
    {
      name = "goal-interval";
      from = "void 0===t&&(c(),t=o.set(u,320))";
      to = "void 0===t&&(c(),t=o.set(u,1200))";
    }
  ];

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
          # /fork opens the fork in a new, focused tmux window.
          (lib.mkIf userCfg.tmux.enable {
            ".omo/agent/extensions/tmux-fork.ts".source = ./tmux-fork.ts;
          })
          # /wt moves the session into a worktree via the `wt` fish function.
          (lib.mkIf (userCfg.tmux.enable && userCfg.worktree.enable) {
            ".omo/agent/extensions/tmux-wt.ts".source = ./tmux-wt.ts;
          })
          # Read-only store symlink; change omo config in omo-jsonc.nix.
          { ".omo/omo.jsonc".source = import ./omo-jsonc.nix { inherit pkgs; }; }
          # Global instructions. omo applies a ~/.omo/rules file only when its
          # frontmatter says so; other modules add their own rules here too.
          {
            ".omo/rules/github.md".text = ''
              ---
              alwaysApply: true
              ---

              ## Never speak as me on GitHub
              Never post or reply to comments on GitHub on my behalf. This includes
              PR/issue comments, review comments and their replies, and reviews —
              whether via `gh`, the GitHub REST/GraphQL API, or any MCP/tool. PR and
              issue bodies are fine. Reading GitHub is fine. If a comment/reply
              genuinely seems needed, draft the text and let me post it myself.
            '';
          }
          # Flexoki light, matching ghostty/kitty/nvim/tmux/opencode.
          { ".omo/agent/themes/flexoki.json".source = ./flexoki.json; }
          # opencode-style prompt, status line, sidebar and tool blocks.
          { ".omo/agent/extensions/ui".source = ./ui; }
        ];

        # omo runs from a copy of itself in ~/.omo/binary-runtime/<version>/ and
        # refreshes that copy only when its size changes, which the same-length
        # byte patches above never do. Swap a stale copy in the way omo does:
        # a rename, so running sessions keep the old inode.
        activation = {
          omoRuntime = {
            after = [ "writeBoundary" ];
            before = [ ];
            data = ''
              rt="$HOME/.omo/binary-runtime/${version}/omo"
              if [ -e "$rt" ] && ! cmp -s ${omo}/bin/omo "$rt"; then
                cp ${omo}/bin/omo "$rt.nix-tmp" && chmod 755 "$rt.nix-tmp" && mv -f "$rt.nix-tmp" "$rt"
              fi
            '';
          };

          # Applies footerPatches above. A fresh version unpacks on its first
          # run, after activation, so the patch then lands on the next rebuild.
          omoFooter = {
            after = [ "writeBoundary" ];
            before = [ ];
            data = ''
              js="$HOME/.omo/binary-runtime/${version}/plugin/extensions/omo.js"
              if [ ! -f "$js" ]; then
                echo "omo: runtime ${version} not unpacked yet; footer patch applies on the next rebuild"
              else
            ''
            + lib.concatMapStrings (p: ''
              from=${lib.escapeShellArg p.from} to=${lib.escapeShellArg p.to}
              if grep -qF -- "$from" "$js"; then
                from="$from" to="$to" ${pkgs.perl}/bin/perl -0777 -pi -e 's/\Q$ENV{from}\E/$ENV{to}/g' "$js"
              elif ! grep -qF -- "$to" "$js"; then
                echo "omo footer patch ${p.name}: target not found, drop or update the patch" >&2
              fi
            '') footerPatches
            + ''
              fi
            '';
          };

          # omo rewrites settings.json itself (tips history, model picks), so it
          # can't be a store symlink: merge the UI keys in on every activation.
          # opencode-like look: fullscreen, Flexoki, no startup header or tips.
          # showHardwareCursor swaps omo's drawn block for the terminal cursor,
          # so it takes the terminal's shape (ghostty/kitty: blinking bar).
          omoSettings = {
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
                collapseChangelog: true,
                showHardwareCursor: true
              }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
            '';
          };
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
