# Grok CLI without the `agent` alias.
#
# llm-agents.nix ships `bin/agent` as a grok launcher. Cursor CLI also
# installs `~/.local/bin/agent` (cursor-agent). Keep only `grok` on PATH so
# `agent` is Cursor.
{ grokPkg, pkgs }:

pkgs.runCommand "grok-cli" {
  meta = grokPkg.meta or { };
  preferLocalBuild = true;
} ''
  mkdir -p "$out/bin"
  ln -s ${grokPkg}/bin/grok "$out/bin/grok"
''
