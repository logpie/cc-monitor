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

# Ensure previous state file exists for slurpfile
[ ! -f "$state_file" ] && echo '{}' > "$state_file"

# Single jq call: compute context + last_message + merge with previous, output final state JSON
tmp_file="$MONITOR_DIR/.${session_id}.state.tmp"
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

    {state: $state, context: $ctx, last_message: $msg}
    ' > "$tmp_file"

mv "$tmp_file" "$state_file"
