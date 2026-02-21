#!/bin/bash
# Claude Code status line reporter
# Reads CC status JSON from stdin, writes enriched JSON to ~/.claude/monitor/
set -euo pipefail

MONITOR_DIR="$HOME/.claude/monitor"
mkdir -p "$MONITOR_DIR"

# Read full JSON from stdin
input=$(cat)

# Extract fields
session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

project_dir=$(echo "$input" | jq -r '.workspace.project_dir // .cwd // empty')
project_name=$(basename "$project_dir")
model=$(echo "$input" | jq -r '.model.display_name // "unknown"')
context_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
context_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

# Get git branch (best effort)
git_branch=""
if [ -n "$project_dir" ] && [ -d "$project_dir/.git" ]; then
    git_branch=$(git -C "$project_dir" branch --show-current 2>/dev/null || echo "")
fi

# Current timestamp
now=$(date +%s)

# Write status file (atomic via temp file)
tmp_file="$MONITOR_DIR/.${session_id}.tmp"
out_file="$MONITOR_DIR/${session_id}.json"

jq -n \
    --arg sid "$session_id" \
    --arg pname "$project_name" \
    --arg branch "$git_branch" \
    --arg model "$model" \
    --argjson ctx_pct "${context_pct:-0}" \
    --argjson ctx_size "${context_size:-200000}" \
    --argjson cost "${cost_usd:-0}" \
    --argjson ts "$now" \
    '{
        session_id: $sid,
        project_name: $pname,
        git_branch: $branch,
        model: $model,
        context_used_pct: $ctx_pct,
        context_window_size: $ctx_size,
        cost_usd: $cost,
        last_updated: $ts
    }' > "$tmp_file"

mv "$tmp_file" "$out_file"

# Also output something for the status line display (optional)
echo "[$model] ${context_pct}%"
