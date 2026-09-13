# Pi default chat: Cursor Composer 2.5 high, not fast, not longctx.
# longctx (MiniCPM5-2B) stays registered for rare dumps; it is too slow
# for herding. Visuals stay MiniCPM-V via `/model minicpm-v-4.5`.
{
  defaultProvider = "cursor";
  defaultModel = "composer-2-5:slow";
  model = "composer-2-5:slow";
  defaultThinkingLevel = "high";
}
