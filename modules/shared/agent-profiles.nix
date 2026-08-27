# Local hipfire catalog: backends (weights) vs lanes (agent policy).
#
# Public API for Pi / Hermes / Grok / Continue / Zed:
#   forge / anvil / feather  — generic lanes (thinking, effort, spec policy)
#   ornith / qwen38          — optional weight ids (swap the resident checkpoint)
#
# Do not put checkpoint names in AI_MODEL / GROK_LOCAL_MODEL. Default lane is
# forge; default backend is ornith. Swap `defaultBackend` when the daily
# checkpoint changes — keep lane ids stable.
#
# Context windows are the *filled* working set Pi/Grok advertise, not the
# model card. hipfire `memory.max_seq` is the GPU fail-closed ceiling.
# Advertising 256k meant Pi never compacted; Qwen 27B dense then died around
# 94k prefill on the R9700 (daemon abort in PrefillBatchScratch / hipFree).
# Keep advertised windows inside that envelope so auto-compact fires first.
rec {
  defaultBackend = "ornith";
  defaultLane = "forge";
  defaultProfile = defaultLane;
  backendModel = backends.${defaultBackend}.tag;
  hipfirePort = 11435;
  listenPort = 8080;
  # Bind the catalog proxy on all interfaces so LAN clients can use
  # http://nixos.local:8080/v1. hipfire serve binds loopback only; LAN
  # traffic must go through this proxy (clamp + think caps + 413).
  listenHost = "0.0.0.0";
  # Catalog default = daily long-session window (forge/anvil/Ornith).
  contextWindow = 49152;
  maxTokens = 16384;

  backends = {
    ornith = {
      tag = "ornith-1.5:35b-a3b";
      aliases = [ "ornith" "ornith-1.5" "ornith1.5" "ornith-1.5:35b-a3b" ];
      displayName = "Ornith";
      description = "Ornith 1.5 35B-A3B MoE (3B active). Default for long sessions. MTP optional. No DFlash draft.";
      contextWindow = 49152;
      maxTokens = 16384;
      maxSeq = 65536;
      kvMode = "q8";
      speculation = [ "off" "mtp" ];
    };
    qwen38 = {
      tag = "qwen3.8:27b";
      aliases = [ "qwen38" "qwen3.8" "qwen3.8:27b" "qwen3.8:latest" ];
      displayName = "Qwen 3.8";
      description = "Qwen3.8 27B dense MQ4. Short/fast (DFlash 2). Do not use for long-form — denser KV, crashed ~94k filled.";
      contextWindow = 32768;
      maxTokens = 8192;
      maxSeq = 65536;
      kvMode = "q8";
      speculation = [ "off" "dflash" "mtp" ];
      draftFile = "qwen38-27b-dflash2.hfq";
    };
  };

  # Pi thinkingLevelMap keys: off/minimal/low/medium/high/xhigh/max.
  # null = hide/clamp away.
  profiles = {
    forge = {
      displayName = "Forge";
      description = "Daily long session: thinking on, medium effort, 2048-token think cap. Compact before ~40k. Stay on Ornith.";
      thinking = true;
      effort = "medium";
      maxThinkTokens = 2048;
      preserveThinking = false;
      contextWindow = 49152;
      maxTokens = 16384;
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
      description = "Hard long-form: thinking on, xhigh, 8192-token think cap. Same compact window as forge. Stay on Ornith.";
      thinking = true;
      effort = "xhigh";
      maxThinkTokens = 8192;
      preserveThinking = false;
      contextWindow = 49152;
      maxTokens = 16384;
      speculation = "off";
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
      description = "Fast short lane: thinking on, low effort, 512-token think cap, greedy. DFlash when the backend has a draft; otherwise MTP/AR.";
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
