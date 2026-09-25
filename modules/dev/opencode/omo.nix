{ pkgs }:
let
  jsonFormat = pkgs.formats.json { };
  package = "oh-my-openagent";
  version = "4.19.4";
  plugin = "${package}@${version}";

  # opencode npm-installs its own plugins at runtime, so there is no
  # derivation to hang `applyPatches` off — the tree lands here instead.
  pkgRoot = "$HOME/.cache/opencode/packages/${plugin}/node_modules/${package}";

  # A tier is one model per provider at the same price level. The call site
  # picks which provider leads, and the other becomes its runtime_fallback
  # counterpart: outages are provider-wide, so a same-provider fallback would
  # die alongside its primary, and staying in-tier keeps a fallback from
  # jumping price. The variant spans the whole chain, so `high.claude "max"`
  # reads as "the high tier, Claude first, all of it at max effort".
  #
  # Every agent and category below takes 5.0.0-beta.84's default primary and
  # effort (the first rung an anthropic/openai login can reach); the
  # counterpart comes from the tier, not from beta's chain. The pin above
  # stays on 4.19.4 until 5.x leaves beta.
  mkTier = models: {
    claude = chain [
      models.claude
      models.gpt
    ];
    gpt = chain [
      models.gpt
      models.claude
    ];
  };
  chain = models: variant: {
    inherit variant;
    model = builtins.head models;
    fallback_models = map (m: {
      inherit variant;
      model = m;
    }) (builtins.tail models);
  };

  ultra = mkTier {
    gpt = "openai/gpt-6-astra";
    claude = "anthropic/claude-fable-5-1";
  };
  high = mkTier {
    gpt = "openai/gpt-5.6-sol";
    claude = "anthropic/claude-opus-5-5";
  };
  mid = mkTier {
    gpt = "openai/gpt-5.6-terra";
    claude = "anthropic/claude-sonnet-5";
  };
  # Hand-built because haiku-4-5 exposes no effort levels, so its rung can't
  # carry the chain's variant. Nothing needs a Claude-led low tier yet.
  low.gpt = variant: {
    inherit variant;
    model = "openai/gpt-5.6-luna-fast";
    fallback_models = [ "anthropic/claude-haiku-4-5" ];
  };
in
{
  default = true;

  home = {
    programs.opencode = {
      settings.plugin = [ plugin ];
      tui.plugin = [ plugin ];
    };

    # Backport of upstream 0fe0ac98 ("route categories through GPT-6 Astra
    # high"), which shipped in 5.0.0-beta.43 but never in the 4.x line.
    # Without it omo's `no-sisyphus-gpt` hook treats every gpt-* model that
    # isn't gpt-5.x as unsupported and force-switches Sisyphus → Hephaestus,
    # so each gpt-6-astra turn gets hijacked. The patch also routes gpt-6 to
    # the gpt-5-5 prompt family and defaults its variant to high, matching
    # upstream. Drop the whole block once the pin above reaches 5.x.
    home.activation.omoGpt6Sisyphus = {
      after = [ "writeBoundary" ];
      before = [ ];
      data = ''
        omo_index="${pkgRoot}/dist/index.js"
        if [ ! -f "$omo_index" ]; then
          echo "omo: ${plugin} not installed yet — GPT-6 patch applies on the next rebuild"
        elif ! grep -q 'function isGpt6Model' "$omo_index"; then
          ${pkgs.gnupatch}/bin/patch -p1 -d "${pkgRoot}" < ${./patches/omo-gpt6-sisyphus.patch}
        fi
      '';
    };

    # Plugin-registered agent overrides live here rather than in
    # programs.opencode.settings.agent.
    #
    # Path matters: omo's "2026-07-opencode-config-unification" migration
    # (ran 2026-09-03) copied ~/.config/opencode/oh-my-openagent.json into
    # ~/.omo/omo.jsonc under the "[opencode]" key and now reads ONLY from
    # there — edits to the old path are silently ignored. `_migrations` is
    # replayed below so omo treats the migration as done and never tries to
    # rewrite this read-only store symlink. `codegraph.daemon` was hand-set
    # in the migrated file; it is kept here so nix owns the whole file.
    home.file.".omo/omo.jsonc".source = jsonFormat.generate "omo.jsonc" {
      "$schema" =
        "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/omo.schema.json";
      codegraph.daemon = false;
      _migrations = [ "2026-07-opencode-config-unification" ];
      # opencode cannot do this natively: its retry re-runs the SAME provider
      # (anomalyco/opencode#7602 is still open, and #20105/#24369/#26192 were
      # all closed unmerged), so a provider outage kills the run. omo's
      # runtime-fallback hook swaps in another model instead.
      #
      # Both defaults below are wrong for this purpose. `enabled` is false, and
      # retry_on_errors is [429 500 502 503 504] — which omits 529, Anthropic's
      # overloaded_error, i.e. the exact "Claude is out" case this exists for.
      "[opencode]".runtime_fallback = {
        enabled = true;
        retry_on_errors = [
          429
          500
          502
          503
          504
          529
        ];
        # Default false, which would strand every agent on its counterpart
        # until the next restart. Primary comes back after cooldown_seconds.
        restore_primary_after_cooldown = true;
      };
      # atlas and sisyphus-junior stay unset: 4.19.4 already resolves them to
      # beta.84's pick, claude-sonnet-5.
      "[opencode]".agents = {
        # The one deviation from beta.84's default effort ("max"): measured
        # on this host, opus-5-5 averages ~1290 reasoning tokens/turn at max
        # against ~90 for opus-5, and most of that went to turns that did not
        # need it. xhigh lands near ~200 — thin enough to feel responsive,
        # twice what "high" spends.
        sisyphus = high.claude "xhigh";
        prometheus = ultra.claude "xhigh";
        metis = ultra.claude "max";
        momus = ultra.gpt "xhigh";
        oracle = high.gpt "xhigh";
        hephaestus = high.gpt "medium";
        "multimodal-looker" = high.gpt "low";
        explore = low.gpt "low";
        librarian = low.gpt "low";
      };
      # quick stays unset: 4.19.4 already resolves it to beta.84's pick,
      # claude-haiku-4-5 "off".
      "[opencode]".categories = {
        ultrabrain = ultra.gpt "max";
        # beta.84 splits deep into deep-low (this chain) and deep-high
        # (ultra.gpt "high"); rename it when the pin reaches 5.x.
        deep = high.gpt "medium";
        "visual-engineering" = ultra.claude "max";
        artistry = ultra.claude "max";
        writing = ultra.claude "low";
        "unspecified-high" = high.claude "max";
        # beta.84 leads with mimo and grok, which we have no login for, so it
        # lands on terra ($2/$12 per Mtok).
        "unspecified-low" = mid.gpt "high";
      };
    };
  };
}
