# Muse Spark (Meta Model API) + Muse Code CLI.
#
# Muse Code is the first-party agent (`muse`). Other harnesses use the same
# model over https://api.meta.ai/v1 — see https://dev.meta.ai/docs/coding-agents/
#
# Chat Completions clients (Zed, Pi, Hermes, Grok) go through a local proxy
# on :8082 that uniquifies Spark's reused tool_call_id `call_0`. OpenCode's
# Responses adapter talks to Meta directly.
#
# Key: ~/.config/meta.env  (MODEL_API_KEY or META_API_KEY). Never commit it.
# OpenCode: /connect after first merge (do not put the key in opencode.json).
{ pkgs, lib, listenPort ? 8082 }:

let
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  museCode = pkgs.callPackage ./muse-code-package.nix { };
  proxyListen = "http://127.0.0.1:${toString listenPort}/v1";
  proxy = pkgs.writeShellApplication {
    name = "muse-spark-proxy";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      export MUSE_SPARK_LISTEN_HOST="''${MUSE_SPARK_LISTEN_HOST:-127.0.0.1}"
      export MUSE_SPARK_LISTEN_PORT="''${MUSE_SPARK_LISTEN_PORT:-${toString listenPort}}"
      exec ${pkgs.python3}/bin/python3 ${./scripts/muse-spark-proxy.py}
    '';
  };
  grokToml = import ./grok-local-model.nix {
    id = "muse";
    apiModel = "muse-spark-1.2";
    displayName = "Muse Spark 1.2";
    description = "Meta Model API via local :${toString listenPort} proxy — export MODEL_API_KEY (~/.config/meta.env)";
    contextWindow = 1048576;
    maxTokens = 131072;
    baseUrl = proxyListen;
    apiKey = "MODEL_API_KEY";
  };
in
{
  inherit museCode grokToml proxy;

  home.packages = [ museCode proxy ];

  home.activation.mergeMuseSparkClients = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [[ -f "$HOME/.config/meta.env" ]]; then
      set -a
      # shellcheck disable=SC1091
      source "$HOME/.config/meta.env"
      set +a
    fi
    export MUSE_SPARK_PROXY_URL=${lib.escapeShellArg proxyListen}
    ${python}/bin/python3 ${./scripts/muse-spark-merge-clients.py} || \
      echo "muse-spark: WARNING client merge failed" >&2
  '';

  systemdUserServices = {
    muse-spark-proxy = {
      Unit = {
        Description = "Uniquify Muse Spark tool_call_id in front of api.meta.ai";
        After = [ "network.target" ];
      };
      Service = {
        ExecStart = "${proxy}/bin/muse-spark-proxy";
        Restart = "on-failure";
        RestartSec = "3";
      };
      # Manual start only. Auto-start would keep PAYG Model API keys in play
      # and bill per token; Muse Code subscription is `muse` + browser /login.
    };
  };

  launchdAgents.muse-spark-proxy = {
    command = "${proxy}/bin/muse-spark-proxy";
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = false;
      StandardOutPath = "/tmp/muse-spark-proxy.out.log";
      StandardErrorPath = "/tmp/muse-spark-proxy.err.log";
    };
  };
}
