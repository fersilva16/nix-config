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
domain. The statusbar refreshes every 15 minutes. `prefix + L` opens a popup:
Enter opens a message, `/` searches, `r` refreshes, Tab flips between grouped
by conversation and one flat list, and `q` closes it. Esc leaves search first,
then closes the popup. `slack.later.groupBy` sets the view it opens in.

The popup displays cached rows immediately while fetching updated data. A `!`
in the statusbar or an error in the popup means the last successful data may
be stale. Sign in again using the same command above, then press `r`.

Slack returns at most 49 items per page, so refresh follows the page cursor,
up to 20 pages, and labels the list truncated if even that is not enough. It
never completes, deletes, or sends anything. Cached snippets and channel names
are private files under `~/.cache/tmux-slack-later`; decrypted cookies live
only in a private temporary directory during refresh.

## Offline checks

```fish
bash modules/chat/slack/later.test.sh
bash modules/chat/slack/later-pane.test.sh
```
