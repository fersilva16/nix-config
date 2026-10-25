# The Slack app. The Slack Later count and popup ship in Limi (limi-suite's
# `slackLater` options).
{ mkUserModule, ... }:
mkUserModule {
  name = "slack";
  casks = [ "slack" ];
}
