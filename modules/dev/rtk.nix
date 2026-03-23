{ username, ... }:
{
  homebrew.brews = [ "rtk" ];

  home-manager.users.${username} = {
    # Claude Code hook: rewrites bash commands to use rtk for token savings.
    # settings.json PreToolUse entry must reference this path.
    home.file.".claude/hooks/rtk-rewrite.sh" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # rtk-hook-version: 2
        # RTK Claude Code hook — rewrites commands to use rtk for token savings.
        # Managed by nix-darwin. Source: https://github.com/rtk-ai/rtk

        if ! command -v jq &>/dev/null; then
          echo "[rtk] WARNING: jq is not installed. Hook cannot rewrite commands." >&2
          exit 0
        fi

        if ! command -v rtk &>/dev/null; then
          echo "[rtk] WARNING: rtk is not installed or not in PATH." >&2
          exit 0
        fi

        RTK_VERSION=$(rtk --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [ -n "$RTK_VERSION" ]; then
          MAJOR=$(echo "$RTK_VERSION" | cut -d. -f1)
          MINOR=$(echo "$RTK_VERSION" | cut -d. -f2)
          if [ "$MAJOR" -eq 0 ] && [ "$MINOR" -lt 23 ]; then
            echo "[rtk] WARNING: rtk $RTK_VERSION is too old (need >= 0.23.0)." >&2
            exit 0
          fi
        fi

        INPUT=$(cat)
        CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

        if [ -z "$CMD" ]; then
          exit 0
        fi

        REWRITTEN=$(rtk rewrite "$CMD" 2>/dev/null) || exit 0

        if [ "$CMD" = "$REWRITTEN" ]; then
          exit 0
        fi

        ORIGINAL_INPUT=$(echo "$INPUT" | jq -c '.tool_input')
        UPDATED_INPUT=$(echo "$ORIGINAL_INPUT" | jq --arg cmd "$REWRITTEN" '.command = $cmd')

        jq -n \
          --argjson updated "$UPDATED_INPUT" \
          '{
            "hookSpecificOutput": {
              "hookEventName": "PreToolUse",
              "permissionDecision": "allow",
              "permissionDecisionReason": "RTK auto-rewrite",
              "updatedInput": $updated
            }
          }'
      '';
    };

    # RTK awareness file for Claude Code
    home.file.".claude/RTK.md".text = ''
      # RTK - Rust Token Killer

      **Usage**: Token-optimized CLI proxy (60-90% savings on dev operations)

      ## Meta Commands (always use rtk directly)

      ```bash
      rtk gain              # Show token savings analytics
      rtk gain --history    # Show command usage history with savings
      rtk discover          # Analyze Claude Code history for missed opportunities
      rtk proxy <cmd>       # Execute raw command without filtering (for debugging)
      ```

      ## Installation Verification

      ```bash
      rtk --version         # Should show: rtk X.Y.Z
      rtk gain              # Should work (not "command not found")
      which rtk             # Verify correct binary
      ```

      ## Hook-Based Usage

      All other commands are automatically rewritten by the Claude Code hook.
      Example: `git status` -> `rtk git status` (transparent, 0 tokens overhead)
    '';

    # OpenCode plugin: rewrites bash/shell commands and compresses built-in tool output via rtk.
    xdg.configFile."opencode/plugins/rtk.ts".text = ''
      import type { Plugin } from "@opencode-ai/plugin"

      // RTK OpenCode plugin — rewrites commands and compresses tool output for token savings.
      // Managed by nix-darwin. Source: https://github.com/rtk-ai/rtk

      export const RtkOpenCodePlugin: Plugin = async ({ $ }) => {
        try {
          await $`which rtk`.quiet()
        } catch {
          console.warn("[rtk] rtk binary not found in PATH — plugin disabled")
          return {}
        }

        return {
          // Rewrite bash/shell commands to use rtk equivalents
          "tool.execute.before": async (input, output) => {
            const tool = String(input?.tool ?? "").toLowerCase()
            if (tool !== "bash" && tool !== "shell") return
            const args = output?.args
            if (!args || typeof args !== "object") return

            const command = (args as Record<string, unknown>).command
            if (typeof command !== "string" || !command) return

            try {
              const result = await $`rtk rewrite ''${command}`.quiet().nothrow()
              const rewritten = String(result.stdout).trim()
              if (rewritten && rewritten !== command) {
                ;(args as Record<string, unknown>).command = rewritten
              }
            } catch {
              // rtk rewrite failed — pass through unchanged
            }
          },

          // Compress built-in tool output through rtk
          "tool.execute.after": async (input, output) => {
            const tool = String(input?.tool ?? "").toLowerCase()
            const args = input?.args as Record<string, unknown> | undefined

            if (tool === "ls") {
              const lsPath = args?.path
              if (typeof lsPath !== "string") return
              try {
                const result = await $`rtk ls ''${lsPath}`.quiet().nothrow()
                const compressed = String(result.stdout).trim()
                if (compressed && result.exitCode === 0) {
                  output.output = compressed
                }
              } catch {
                // rtk ls failed — keep original output
              }
            }

            if (tool === "grep") {
              const pattern = args?.pattern
              const grepPath = args?.path ?? "."
              const include = args?.include
              if (typeof pattern !== "string" || typeof grepPath !== "string") return
              try {
                const globArgs = typeof include === "string" ? `--glob ''${include}` : ""
                const result = await $`rtk grep ''${pattern} ''${grepPath} ''${globArgs}`.quiet().nothrow()
                const compressed = String(result.stdout).trim()
                if (compressed && result.exitCode === 0) {
                  output.output = compressed
                }
              } catch {
                // rtk grep failed — keep original output
              }
            }
          },
        }
      }
    '';
  };
}
