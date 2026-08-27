# Local hipfire catalog: backends (weights) vs lanes (agent policy).
#
# Public API for Pi / Hermes / Grok / Continue / Zed:
#   forge / anvil / feather  — generic lanes (thinking, effort, spec policy)
#   ornith / qwen38          — optional weight ids (swap the resident checkpoint)
#
# Do not put checkpoint names in AI_MODEL / GROK_LOCAL_MODEL. Default lane is
# forge; default backend is ornith. Swap `defaultBackend` when the daily
# checkpoint changes — keep lane ids stable.
rec {
  defaultBackend = "ornith";
  defaultLane = "forge";
  defaultProfile = defaultLane;
  backendModel = backends.${defaultBackend}.tag;
  hipfirePort = 11435;
  listenPort = 8080;
  contextWindow = 262144;
  maxTokens = 32768;

  backends = {
    ornith = {
      tag = "ornith-1.5:35b-a3b";
      aliases = [ "ornith" "ornith-1.5" "ornith1.5" "ornith-1.5:35b-a3b" ];
      displayName = "Ornith";
      description = "Ornith 1.5 35B-A3B MoE (3B active). AR default; MTP optional. No DFlash draft.";
      contextWindow = 262144;
      maxTokens = 32768;
      maxSeq = 262144;
      kvMode = "q8";
      speculation = [ "off" "mtp" ];
    };
    qwen38 = {
      tag = "qwen3.8:27b";
      aliases = [ "qwen38" "qwen3.8" "qwen3.8:27b" "qwen3.8:latest" ];
      displayName = "Qwen 3.8";
      description = "Qwen3.8 27B dense MQ4. DFlash 2 when the fast lane asks for it.";
      contextWindow = 262144;
      maxTokens = 32768;
      maxSeq = 262144;
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
      description = "Daily lane: thinking on, medium effort, full context.";
      thinking = true;
      effort = "medium";
      contextWindow = 262144;
      maxTokens = 32768;
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
      description = "Hard lane: thinking on, xhigh effort, full context.";
      thinking = true;
      effort = "xhigh";
      contextWindow = 262144;
      maxTokens = 32768;
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
      description = "Fast lane: thinking off, greedy. DFlash when the backend has a draft; otherwise AR.";
      thinking = false;
      reasoning = false;
      contextWindow = 65536;
      maxTokens = 8192;
      temperature = 0;
      presencePenalty = 0;
      speculation = "dflash-if-capable";
    };
  };
}
