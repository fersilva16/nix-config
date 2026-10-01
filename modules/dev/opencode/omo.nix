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
  # One entry of a Native `models` chain (5.x shape).
  rung = model: reasoning: { inherit model reasoning; };

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
    # in the migrated file; it is kept here so nix owns the whole file. It
    # sits under "[opencode]" because OmO Native reads the same file and has
    # no `codegraph` key; the plugin merges that block over the top level.
    home.file.".omo/omo.jsonc".source = jsonFormat.generate "omo.jsonc" {
      "$schema" =
        "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/omo.schema.json";
      "[opencode]".codegraph.daemon = false;
      # OmO Native's agent memory: per-cwd stores under ~/.omo/memory that
      # get injected into prompts, plus background fact extraction,
      # reflection and recall. Off: one store per worktree name fragments
      # it, it writes guesses down as rules, and its PR-state notes go stale
      # within hours. Durable rules live in CLAUDE.md/AGENTS.md instead.
      # `recall` has its own switch, so it is turned off explicitly too.
      memory = {
        enabled = false;
        recall.enabled = false;
      };
      # OmO Native runs these rewrites of this file too, and each one it
      # cannot write (read-only store) leaves ~/.omo/.migration-journal.json
      # behind to retry on every start. reasoning-unification converts
      # model/variant/fallback_models into 5.x `models = [{ model, reasoning }]`
      # and category-deep-split renames `deep` to `deep-low` — both break the
      # 4.19.4 plugin, which reads only the old shape. Drop them once the pin
      # reaches 5.x and the blocks below move to the new shape.
      _migrations = [
        "2026-07-opencode-config-unification"
        "2026-08-reasoning-unification"
        "2026-09-category-deep-split"
      ];
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
      # OmO Native reads this same file but its own scope. These are omo
      # 5.1.2's builtin chains (plugin/extensions/omo-task.js), copied so
      # they can be tuned here, keeping only the rungs our two logins reach:
      # anthropic-subscription and chatgpt-subscription. Rungs that differ
      # only by an unreachable provider (copilot, opencode) are collapsed.
      # Written in 5.x `models = [{ model, reasoning }]` shape, which Native
      # reads natively; the 4.19.4 plugin never sees this scope.
      # `[native]`, not the older `[senpi]` spelling: native reads both, but
      # its harness-native-rename migration would try to rewrite the latter.
      "[native]" = {
        agents = {
          explore.models = [
            (rung "openai/gpt-6-luna-fast" "low")
            "anthropic/claude-haiku-4-5"
          ];
          librarian.models = [
            (rung "openai/gpt-6-luna-fast" "low")
            "anthropic/claude-haiku-4-5"
          ];
          "plan-consultant".models = [
            (rung "anthropic/claude-fable-5-1" "max")
            (rung "anthropic/claude-opus-5-5" "max")
          ];
          "plan-reviewer".models = [
            (rung "openai/gpt-6-astra" "xhigh")
            (rung "openai/gpt-6-astra" "high")
            (rung "anthropic/claude-opus-5-5" "max")
          ];
        };
        categories = {
          "visual-engineering".models = [
            (rung "anthropic/claude-fable-5-1" "max")
            (rung "anthropic/claude-opus-5-5" "max")
          ];
          architect.models = [ (rung "anthropic/claude-fable-5-1" "max") ];
          ultrabrain.models = [
            (rung "openai/gpt-6-astra" "max")
            (rung "openai/gpt-5.6-sol" "max")
          ];
          "deep-low".models = [
            (rung "openai/gpt-5.6-sol" "medium")
            (rung "openai/gpt-5.6-sol-fast" "medium")
          ];
          "deep-high".models = [ (rung "openai/gpt-6-astra" "xhigh") ];
          artistry.models = [
            (rung "anthropic/claude-fable-5-1" "max")
            (rung "anthropic/claude-opus-5-5" "max")
          ];
          quick.models = [
            (rung "openai/gpt-6-luna-fast" "low")
            (rung "anthropic/claude-haiku-4-5" "off")
          ];
          "unspecified-low".models = [
            (rung "anthropic/claude-sonnet-5-5" "medium")
            (rung "openai/gpt-5.6-terra" "high")
            (rung "anthropic/claude-sonnet-5" "low")
          ];
          "unspecified-high".models = [ (rung "anthropic/claude-opus-5-5" "medium") ];
          writing.models = [
            (rung "anthropic/claude-opus-5-5" "low")
            (rung "anthropic/claude-opus-4-6" "max")
          ];
        };
      };
    };
  };
}
