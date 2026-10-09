# ollama — local LLMs.
#
# darwin: just the CLI.
#
# linux (polaris: RTX 5070 Ti, 16 GB): a socket-activated CUDA server, so
# there is nothing to start or stop by hand. systemd holds :11434; the first
# connection (opencode on vega, `ollama run` on polaris, curl) starts
# ollama-proxy, which pulls in ollama. The proxy exits after idleTimeout with
# no traffic, and ollama is bound to it, so it stops too and frees the VRAM.
# Nothing runs at boot except the listening socket.
#
#   ollama-proxy.socket   :11434, always listening
#   ollama-proxy.service  systemd-socket-proxyd -> 127.0.0.1:11435
#   ollama.service        the real server on :11435
#
# Manual control still works: `systemctl start ollama` brings the proxy up
# with it (same idle timeout), `systemctl stop ollama` stops both at once.
#
# The backend listens on 0.0.0.0, not loopback: on a loopback listener
# ollama rejects any Host header other than localhost/the bare hostname, so
# `polaris.<tailnet>.ts.net` would get 403. The backend port is not opened in
# the firewall; only :11434 is, and only on tailscale0.
#
# CUDA is unfree, so cache.nixos.org never has it; the nixos-cuda cache does.
# That cache is declared at the host level (modules/hosts/polaris.nix), not
# here, so it is already in nix.conf before ollama is first enabled.
{
  mkUserModule,
  forPlatform,
  pkgs,
  lib,
  ...
}:
let
  port = 11434;
  backendPort = 11435;
  idleTimeout = "30min";

  # Hold ollama in "activating" until it answers, so the proxy (ordered
  # after it) never forwards the first request to a closed port.
  waitReady = pkgs.writeShellScript "ollama-wait-ready" ''
    until ${lib.getExe pkgs.curl} -sf http://127.0.0.1:${toString backendPort}/ >/dev/null; do
      sleep 0.1
    done
  '';
in
mkUserModule {
  name = "ollama";

  extraOptions.models = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "qwen3:14b" ];
    description = ''
      Models always present on the server (linux). Pulled the next time
      ollama starts; manually pulled models are kept alongside them.
    '';
  };

  system =
    { enabledUsers }:
    forPlatform {
      linux = {
        # Also puts the CUDA build's CLI on PATH.
        services.ollama = {
          enable = true;
          package = pkgs.ollama-cuda;
          host = "0.0.0.0";
          port = backendPort;
          # Default is 4K below 24 GB of VRAM, which an agent's system prompt
          # plus tool schemas alone can fill. 32K still fits next to a
          # 14-15 GB model on 16 GB; `ollama ps` should show 100% GPU.
          environmentVariables.OLLAMA_CONTEXT_LENGTH = "32768";
          loadModels = lib.unique (lib.concatMap (u: u.ollama.models) (lib.attrValues enabledUsers));
          # Manual `ollama pull`s stay; removing one from the list does not
          # delete it (`ollama rm` does).
          syncModels = false;
        };

        systemd = {
          sockets.ollama-proxy = {
            wantedBy = [ "sockets.target" ];
            listenStreams = [ (toString port) ];
          };

          services = {
            ollama-proxy = {
              description = "Socket-activated proxy for ollama";
              requires = [ "ollama-proxy.socket" ];
              bindsTo = [ "ollama.service" ];
              after = [
                "ollama-proxy.socket"
                "ollama.service"
              ];
              serviceConfig.ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=${idleTimeout} 127.0.0.1:${toString backendPort}";
            };

            ollama = {
              # Never started at boot; the proxy pulls it in on demand.
              wantedBy = lib.mkForce [ ];
              # Stops when the proxy idles out; a manual start brings the proxy up.
              bindsTo = [ "ollama-proxy.service" ];
              serviceConfig.ExecStartPost = waitReady;
            };

            # Upstream also wants this at boot, which would start ollama with it.
            # Run it only when ollama starts; it talks to the backend directly.
            ollama-model-loader.wantedBy = lib.mkForce [ "ollama.service" ];
          };
        };

        networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];
      };
    };

  # On linux the service already ships the CLI; a second (CPU) copy in the
  # home profile would shadow the CUDA one on PATH.
  home.home.packages = forPlatform { darwin = [ pkgs.ollama ]; };
}
