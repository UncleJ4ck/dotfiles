# Serena is registered at USER scope now, so this wrapper is retired.
#
# It used to define a `claude()` function that registered Serena per-project, but
# that only fired for a bare `claude` typed in this shell. Launching from the
# desktop app, an IDE, or a cron/headless run got nothing, and the mechanism was
# invisible when it failed: `claude mcp add` never validates the command, so when
# upstream renamed the entry point from `serena-mcp-server` to
# `serena start-mcp-server`, registration kept "succeeding" while Serena's tools
# never appeared.
#
# The replacement is one user-scope registration using `--project-from-cwd`,
# which auto-detects the repo root at launch and starts cleanly outside a repo
# too. Every launch path gets it, nothing to remember:
#
#   claude mcp add serena -s user -- uvx --from git+https://github.com/oraios/serena \
#     serena start-mcp-server --context ide-assistant --project-from-cwd --transport stdio
#
# Trade-off taken deliberately: the old 200-tracked-file gate kept Serena out of
# small repos. Tool schemas are deferred now, so an idle server costs a process
# and its language-server boot, not context. Automatic beat lean.
#
# SERENA_OFF no longer applies. To disable: `claude mcp remove serena -s user`.
# Tests for the retired wrapper are gone with it; the live check is that
# `claude mcp list` shows serena connected.
