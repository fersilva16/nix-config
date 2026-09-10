# Slack Later in tmux

This opt-in integration uses an isolated Chrome profile, not desktop Slack or
the normal Chrome "Telepatia" profile. It reads undocumented Slack endpoints;
session expiry and workspace security policies still apply.

## Sign in or renew the session

Run this in your shell, then complete Slack sign-in in the new browser window:

```fish
open -na "Google Chrome" --args \
  --user-data-dir="$HOME/.local/share/tmux-slack-later/chrome" \
  --profile-directory=Default --no-first-run --no-default-browser-check \
  https://telepatiaworkspace.slack.com/
```

Choose to use Slack in the browser. Do not import another profile or enable
Chrome Sync. Signing in here is separate from signing into desktop Slack.
Chrome Safe Storage in the macOS login Keychain decrypts this profile's cookies;
approve access if prompted. Never paste credentials into Nix configuration.

## Use

Enable `slack.later.enable` and set `slack.later.workspace` to the exact workspace
domain. The statusbar refreshes every 15 minutes. `prefix + L` opens a right-hand
pane: Enter opens a message, `/` searches, `r` refreshes, and `q` closes it.
Esc leaves search first, then closes the pane from menu mode.

The pane displays cached rows immediately while fetching updated data. A `!`
in the statusbar or an error in the pane means the last successful data may be
stale. Sign in again using the same command above, then press `r` in the pane.

Slack accepts fewer than 50 items per page. This viewer shows up to 49, with an
explicit truncation label when more exist. It never completes, deletes, or sends
anything. Cached snippets are private files under `~/.cache/tmux-slack-later`;
decrypted cookies live only in a private temporary directory during refresh.

## Offline checks

```fish
bash modules/chat/slack/later.test.sh
bash modules/chat/slack/later-pane.test.sh
```
