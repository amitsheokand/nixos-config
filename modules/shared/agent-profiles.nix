# Stable agent-profile names for the local hipfire OpenAI endpoint.
#
# These names are the public API (Pi / Grok / Hermes / Cursor Continue).
# Swap `backendModel` when the checkpoint changes — do not rename profiles.
# Cursor analogue: forge = Composer (daily), anvil = Grok (hard),
# feather = fastest no-think lane.
#
# Speed vs quality is thinking / effort on one loaded checkpoint. Feather
# is the DFlash 2 decode lane (same qwen3.8:27b + qwen38-27b-dflash2.hfq).
# 64k on feather is the advertised client window.
{
  backendModel = "qwen3.8:27b";
  hipfirePort = 11435;
  listenPort = 8080;
  contextWindow = 262144;
  maxTokens = 32768;
  defaultProfile = "forge";

  # Pi thinkingLevelMap keys: off/minimal/low/medium/high/xhigh/max.
  # null = hide/clamp away. Qwen3.8 has no native `high`; map it onto
  # the profile's default lane so leftover defaultThinkingLevel=high
  # does not silently become a different product.
  profiles = {
    forge = {
      displayName = "Forge";
      description = "Default long-session agent: thinking on, medium effort, moderate speed.";
      thinking = true;
      effort = "medium";
      contextWindow = 262144;
      maxTokens = 32768;
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
      description = "Slow xhigh-effort thinking for hard, long-horizon work.";
      thinking = true;
      effort = "xhigh";
      contextWindow = 262144;
      maxTokens = 32768;
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
      description = "Fastest subagent: DFlash 2, thinking off, greedy, 64k context.";
      thinking = false;
      reasoning = false;
      contextWindow = 65536;
      maxTokens = 8192;
      # Greedy: DFlash 2 chain/verify is the validated fast path. Instruct
      # sampling (temp 0.7 / presence_penalty 1.5) forces AR.
      temperature = 0;
      presencePenalty = 0;
      speculation = "dflash";
    };
  };
}
