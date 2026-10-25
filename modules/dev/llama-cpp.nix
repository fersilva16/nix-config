# llama.cpp — llama-cli / llama-server, for what ollama can't do, e.g.
# `--n-cpu-moe` to keep a big MoE's experts in RAM and the rest on the GPU.
#
# linux (polaris): CUDA build, prebuilt on cache.nixos-cuda.org (declared in
# modules/hosts/polaris.nix). darwin: the default build already uses Metal.
#
# With an omo home, omo gets a `llama-cpp` provider for a llama-server on
# :8080 in single-model mode (started with -hf/-m), which serves whatever it
# loaded under any model id. omo's built-in llama.cpp provider needs router
# mode instead. The model's context must match the server's `-c`.
{
  mkUserModule,
  forPlatform,
  pkgs,
  lib,
  ...
}:
mkUserModule {
  name = "llama-cpp";
  home =
    { userCfg, ... }:
    {
      home.packages = [
        (forPlatform {
          darwin = pkgs.llama-cpp;
          linux = pkgs.llama-cpp.override { cudaSupport = true; };
        })
      ];
      home.file.".omo/agent/models.json" = lib.mkIf userCfg.omo-home.enable {
        text = builtins.toJSON {
          providers.llama-cpp = {
            baseUrl = "http://127.0.0.1:8080/v1";
            api = "openai-completions";
            # omo hides keyless providers; llama-server ignores the key.
            apiKey = "none";
            compat = {
              supportsDeveloperRole = false;
              supportsReasoningEffort = false;
            };
            models = [
              {
                id = "huihui-ai/Huihui-Qwen3.5-122B-A10B-abliterated-GGUF:Q4_K";
                name = "Qwen3.5 122B abliterated (local)";
                contextWindow = 131072;
              }
            ];
          };
        };
      };
    };
}
