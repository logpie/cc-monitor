#!/bin/bash
# Claude Code hook handler for CC Monitor
# Writes session state to ~/.claude/monitor/.{session_id}.state as JSON
# Optimized: everything computed in a single jq pipeline
set -euo pipefail

state="${1:-unknown}"
input=$(cat)

session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

MONITOR_DIR="$HOME/.claude/monitor"
state_file="$MONITOR_DIR/.${session_id}.state"

# --- Per-session lock (mkdir is atomic on all POSIX systems) ---
lockdir="$MONITOR_DIR/.${session_id}.lock"
lockpid="$lockdir/pid"
got_lock=false

cleanup() {
    if $got_lock; then
        rm -f "$lockpid"
        rmdir "$lockdir" 2>/dev/null || true
    fi
    # Clean up orphaned tmp file on abnormal exit
    rm -f "$MONITOR_DIR/.${session_id}.state.tmp.$$"
}
trap cleanup EXIT

attempts=0
while ! mkdir "$lockdir" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [ $attempts -gt 100 ]; then
        # Check if lock holder is still alive
        holder=$(cat "$lockpid" 2>/dev/null || echo "")
        if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
            # Holder is dead — safe to steal
            rm -f "$lockpid"
            rmdir "$lockdir" 2>/dev/null || true
            if mkdir "$lockdir" 2>/dev/null; then
                break
            fi
        fi
        # Holder alive or steal failed — give up, run unlocked
        # (better than blocking a hook indefinitely)
        break
    fi
    sleep 0.01
done

if [ -d "$lockdir" ]; then
    echo $$ > "$lockpid"
    got_lock=true
fi

# --- Critical section (read-modify-write under lock) ---

# Ensure previous state file exists for slurpfile (no-truncate create)
[ ! -f "$state_file" ] && printf '{}' > "$state_file"

# Handle late notification_permission: suppress if session already moved to working.
# Notification(permission_prompt) fires ~6s after PermissionRequest. If the user already
# approved (PreToolUse set state to "working"), this late notification would incorrectly
# revert the state to waiting_permission. Skip the write in that case.
# Safe from TOCTOU: lock ensures no concurrent write between read and exit.
if [ "$state" = "notification_permission" ]; then
    prev_state=$(jq -r '.state // ""' "$state_file" 2>/dev/null || echo "")
    if [ "$prev_state" = "working" ]; then
        exit 0
    fi
    state="waiting_permission"
fi

# Single jq call: compute context + last_message + merge with previous, output final state JSON
tmp_file="$MONITOR_DIR/.${session_id}.state.tmp.$$"
echo "$input" | jq -n \
    --arg state "$state" \
    --slurpfile prev "$state_file" \
    --slurpfile inp /dev/stdin \
    '
    ($inp[0] // {}) as $in |
    ($prev[0] // {}) as $p |
    ($in.tool_name // "") as $tool |
    ($in.tool_input // {}) as $ti |

    # Compute context
    (if $state == "working" and ($tool | length > 0) then
        if $tool == "Edit" or $tool == "Write" or $tool == "Read" then
            if ($ti.file_path // "") != "" then
                $tool + " " + ($ti.file_path | split("/") | last)
            else $tool end
        elif $tool == "Bash" then
            ($ti.command // "" | split("\n")[0] | .[0:40]) as $cmd |
            if $cmd != "" then "$ " + $cmd else "" end
        elif $tool == "Grep" or $tool == "Glob" then
            ($ti.pattern // "" | .[0:30]) as $p |
            if $p != "" then "Search: " + $p else "" end
        elif $tool == "Task" then
            ($ti.description // "" | .[0:30]) as $d |
            if $d != "" then "Agent: " + $d else "Running agent" end
        elif $tool == "WebSearch" then
            ($ti.query // "" | .[0:30]) as $q |
            if $q != "" then "Search: " + $q else "Web search" end
        elif $tool == "WebFetch" then "Fetching web page"
        else $tool end
    else "" end) as $new_ctx |

    # Compute last_message
    (if $state == "idle" then
        ($in.last_assistant_message // "" | split("\n") | map(select(length > 0)) | first // "" | gsub("^[#*>` -]+"; "") | .[0:100])
    else "" end) as $new_msg |

    # Merge: use new value if non-empty, else preserve previous
    (if $new_ctx != "" then $new_ctx else ($p.context // "") end) as $ctx |
    (if $new_msg != "" then $new_msg else ($p.last_message // "") end) as $msg |

    # Manage agents array for subagent lifecycle
    # Clear agents on terminal states (idle, session_start) to prevent stale entries
    # from rejected/crashed subagents that never fired SubagentStop.
    ($p.agents // []) as $prev_agents |
    (if $state == "idle" then []
    elif $state == "subagent_start" then
        ($in.agent_id // "") as $aid |
        ($in.agent_type // "") as $atype |
        if $aid != "" then
            ($prev_agents | map(select(.id != $aid))) + [{"id": $aid, "type": $atype}]
        else $prev_agents end
    elif $state == "subagent_stop" then
        ($in.agent_id // "") as $aid |
        if $aid != "" then
            $prev_agents | map(select(.id != $aid))
        else $prev_agents end
    else $prev_agents end) as $agents |

    # For subagent events, keep state as working
    (if $state == "subagent_start" or $state == "subagent_stop" then "working" else $state end) as $final_state |

    {state: $final_state, context: $ctx, last_message: $msg, agents: $agents}
    ' > "$tmp_file"

mv "$tmp_file" "$state_file"
