# Serena as the default code-context layer for Claude Code, scoped to large repos.
#
# A bare `claude` inside a sizable git repo registers Serena's MCP (LSP-grounded
# symbol navigation + editing) for that project, then launches Claude Code.
# Small repos, non-repos, ~/, flagged launches, or SERENA_OFF=1 fall through to
# plain `claude` so daily sessions stay lean (native Grep/Glob/Read + the
# ast-grep MCP already cover small-repo navigation at zero added context).
#
# Gate: only repos with >= SERENA_MIN_FILES tracked files (default 200).
# Escape: `SERENA_OFF=1 claude`, or pass any flag (e.g. `claude --resume`).
# First launch in a repo downloads Serena via uvx (one-time, slow). The MCP is
# registered at local scope (stored per-project in ~/.claude.json, not committed
# to the repo). All inner `claude` calls use `command claude` to avoid recursion.
claude() {
  if [[ $# -ne 0 || -n ${SERENA_OFF:-} ]] \
     || (( ! $+commands[uvx] )) \
     || ! git rev-parse --is-inside-work-tree &>/dev/null; then
    command claude "$@"
    return
  fi
  local root nfiles
  root=$(git rev-parse --show-toplevel)
  nfiles=$(git -C "$root" ls-files | wc -l)
  if (( nfiles >= ${SERENA_MIN_FILES:-200} )); then
    command claude mcp list 2>/dev/null | grep -q 'serena' \
      || command claude mcp add serena -- \
           uvx --from git+https://github.com/oraios/serena serena-mcp-server \
           --context ide-assistant --project "$root" >/dev/null 2>&1
  fi
  command claude
}
