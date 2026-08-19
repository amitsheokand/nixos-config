{ pkgs, lib, user, ... }:

let
  script = name: builtins.readFile (./scripts + "/${name}");
in
{
  ".local/bin/ai-endpoint" = {
    text = script "ai-endpoint";
    executable = true;
  };

  ".local/bin/ai" = {
    text = script "ai";
    executable = true;
  };

  ".local/bin/ai-submit" = {
    text = script "ai-submit";
    executable = true;
  };

  ".local/bin/ai-coordinator" = {
    text = script "ai-coordinator";
    executable = true;
  };

  ".local/bin/ai-worker" = {
    text = script "ai-worker";
    executable = true;
  };

  ".local/bin/ai-claude" = {
    text = script "ai-claude";
    executable = true;
  };

  ".local/bin/ai-codex" = {
    text = script "ai-codex";
    executable = true;
  };

  # Codex reads the host-specific profile installed by the Darwin/NixOS
  # Home Manager module and sends requests to that host's local OpenAI API.
  ".local/bin/codex-local" = {
    text = script "codex-local";
    executable = true;
  };

  # Grok Build supports OpenAI-compatible custom endpoints. Keep this opt-in
  # so the normal Grok cloud profile and its marketplace remain untouched.
  ".local/bin/grok-local" = {
    text = script "grok-local";
    executable = true;
  };

  ".local/bin/ai-team" = {
    text = script "ai-team";
    executable = true;
  };
}
