# Local hipfire catalog: backends (weights) vs lanes (agent policy).
#
# Public API for Pi / Hermes / Grok / Continue / Zed:
#   forge / anvil / feather  — generic lanes (thinking, effort, spec policy)
#   qwen38                   — daily weight id
#   ornith                   — official MQ4R + Sharp jinja sidecar (forge/ornith)
#
# Do not put checkpoint names in AI_MODEL / GROK_LOCAL_MODEL. Default lane is
# forge; default backend is qwen38 (mq4-pro). Swap `defaultBackend` when the
# daily checkpoint changes — keep lane ids stable.
#
# Context windows are the *filled* working set Pi/Grok advertise, not the
# model card. hipfire `memory.max_seq` is the GPU fail-closed ceiling.
# Advertising 256k meant Pi never compacted; Qwen 27B dense then died around
# 94k prefill on the R9700 (daemon abort in PrefillBatchScratch / hipFree).
# Keep advertised windows inside that envelope so auto-compact fires first.
rec {
  defaultBackend = "qwen38";
  defaultLane = "forge";
  defaultProfile = defaultLane;
  backendModel = backends.${defaultBackend}.tag;
  hipfirePort = 11435;
  listenPort = 8080;
  # Bind the catalog proxy on all interfaces so LAN clients can use
  # http://nixos.local:8080/v1. hipfire serve binds loopback only; LAN
  # traffic must go through this proxy (clamp + think caps + 413).
  listenHost = "0.0.0.0";
  # Catalog default = daily long-session window (forge/anvil).
  contextWindow = 49152;
  maxTokens = 16384;

  backends = {
    ornith = {
      tag = "ornith-1.5:35b-a3b-mq4r";
      aliases = [ "ornith" "ornith-1.5" "ornith1.5" "ornith-1.5:35b-a3b" "ornith-1.5:35b-a3b-mq4r" ];
      displayName = "Ornith";
      description = "Official Ornith 1.5 MQ4R (uniform qt44) with Tiel Sharp v22.4 jinja sidecar. Daily lanes stay on Qwen; pick ornith or forge/ornith to swap.";
      available = true;
      contextWindow = 65536;
      maxTokens = 16384;
      maxSeq = 65536;
      kvMode = "q8";
      speculation = [ "off" "mtp" ];
    };
    qwen38 = {
      tag = "qwen3.8:27b-mq4-pro";
      aliases = [ "qwen38" "qwen3.8" "qwen3.8:27b" "qwen3.8:latest" "qwen3.8:27b-mq4-pro" ];
      displayName = "Qwen 3.8";
      description = "Qwen3.8 27B mq4-pro. Daily backend for forge/anvil/feather. DFlash on feather. Advertised 32k/48k; GPU cap 65k.";
      contextWindow = 49152;
      maxTokens = 16384;
      maxSeq = 65536;
      kvMode = "q8";
      speculation = [ "off" "dflash" "mtp" ];
      draftFile = "qwen38-27b-dflash-mq4.hfq";
    };
  };

  # Pi thinkingLevelMap keys: off/minimal/low/medium/high/xhigh/max.
  # null = hide/clamp away.
  profiles = {
    forge = {
      displayName = "Forge";
      description = "Daily long session on Qwen 3.8: thinking on, medium, 4096-token think cap, greedy AR. Compact before ~40k.";
      backend = "qwen38";
      thinking = true;
      effort = "medium";
      maxThinkTokens = 4096;
      preserveThinking = false;
      contextWindow = 49152;
      maxTokens = 16384;
      temperature = 0;
      presencePenalty = 0;
      speculation = "off";
      thinkingLevelMap = {
        off = null;
        minimal = null;
        low = "low";
        medium = "medium";
        high = "medium";
        xhigh = "xhigh";
        max = "xhigh";
      };
    };
    anvil = {
      displayName = "Anvil";
      description = "Hard long-form on Qwen 3.8: thinking on, xhigh, 8192-token think cap, DFlash. Same compact window as forge.";
      backend = "qwen38";
      thinking = true;
      effort = "xhigh";
      maxThinkTokens = 8192;
      preserveThinking = false;
      contextWindow = 49152;
      maxTokens = 16384;
      temperature = 0;
      presencePenalty = 0;
      speculation = "dflash-if-capable";
      thinkingLevelMap = {
        off = null;
        minimal = null;
        low = null;
        medium = null;
        high = "xhigh";
        xhigh = "xhigh";
        max = "xhigh";
      };
    };
    feather = {
      displayName = "Feather";
      description = "Fast short lane on Qwen 3.8: thinking on, low effort, 512-token think cap, greedy, DFlash. Compact at 32k.";
      backend = "qwen38";
      thinking = true;
      effort = "low";
      # Explicit cap: Qwen3.8 "low" is a prompt instruction, not a token budget.
      maxThinkTokens = 512;
      preserveThinking = false;
      contextWindow = 32768;
      maxTokens = 8192;
      temperature = 0;
      presencePenalty = 0;
      speculation = "dflash-if-capable";
      thinkingLevelMap = {
        off = null;
        minimal = "low";
        low = "low";
        medium = "low";
        high = "low";
        xhigh = "low";
        max = "low";
      };
    };
  };
}
