#!/usr/bin/env bash
# Claude Code Status Line
# Line 1: current folder | git branch | running model
# Line 2: context window usage bar | daily token budget usage bar

# ---------------------------------------------------------------------------
# Configuration — override via environment or edit here
# ---------------------------------------------------------------------------
DAILY_BUDGET=${CLAUDE_DAILY_TOKEN_BUDGET:-1000000}
DAILY_FILE="${HOME}/.claude/daily_usage.json"

# ---------------------------------------------------------------------------
# Read and parse JSON from stdin
# ---------------------------------------------------------------------------
INPUT=$(cat)

MODEL=$(      echo "$INPUT" | jq -r '.model.display_name // "Unknown"')
CWD=$(        echo "$INPUT" | jq -r '.cwd // ""')
CTX_USED=$(   echo "$INPUT" | jq -r '(.context_window.used_percentage // 0) | floor')
SESSION_ID=$( echo "$INPUT" | jq -r '.session_id // ""')
TOTAL_IN=$(   echo "$INPUT" | jq -r '(.context_window.total_input_tokens // 0) | floor')
TOTAL_OUT=$(  echo "$INPUT" | jq -r '(.context_window.total_output_tokens // 0) | floor')
SESSION_TOKENS=$(( TOTAL_IN + TOTAL_OUT ))

# ---------------------------------------------------------------------------
# Line 1 data: folder name and git branch
# ---------------------------------------------------------------------------
FOLDER=$(basename "$CWD")
GIT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || true)
# Detached HEAD fallback
[[ -z "$GIT_BRANCH" ]] && GIT_BRANCH=$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null || true)

# ---------------------------------------------------------------------------
# Daily token tracking (persisted in ~/.claude/daily_usage.json)
# ---------------------------------------------------------------------------
TODAY=$(date +%Y-%m-%d)

# Reset file if it's a new day or file doesn't exist / is corrupt
FILE_DATE=$(jq -r '.date // ""' "$DAILY_FILE" 2>/dev/null || echo "")
if [[ "$FILE_DATE" != "$TODAY" ]]; then
    printf '{"date":"%s","sessions":{}}' "$TODAY" > "$DAILY_FILE"
fi

# Update this session's token count (only increases monotonically)
if [[ -n "$SESSION_ID" && "$SESSION_TOKENS" -gt 0 ]]; then
    PREV=$(jq -r --arg sid "$SESSION_ID" '.sessions[$sid] // 0' "$DAILY_FILE" 2>/dev/null || echo 0)
    if [[ "$SESSION_TOKENS" -gt "$PREV" ]]; then
        TMP=$(mktemp)
        if jq --arg sid "$SESSION_ID" --argjson tok "$SESSION_TOKENS" \
                '.sessions[$sid] = $tok' "$DAILY_FILE" > "$TMP" 2>/dev/null; then
            mv "$TMP" "$DAILY_FILE"
        else
            rm -f "$TMP"
        fi
    fi
fi

DAILY_TOKENS=$(jq '[.sessions | to_entries[] | .value] | add // 0' "$DAILY_FILE" 2>/dev/null || echo 0)
DAILY_PCT=$(( (DAILY_TOKENS * 100) / DAILY_BUDGET ))
[[ $DAILY_PCT -gt 100 ]] && DAILY_PCT=100

# ---------------------------------------------------------------------------
# ANSI colors
# ---------------------------------------------------------------------------
R='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BLUE='\033[34m'
WHITE='\033[37m'

# ---------------------------------------------------------------------------
# Progress bar builder: make_bar <filled_pct> <width>
# ---------------------------------------------------------------------------
make_bar() {
    local pct=$1 width=$2
    local filled=$(( (pct * width + 50) / 100 ))
    [[ $filled -gt $width ]] && filled=$width
    local empty=$(( width - filled ))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty;  i++)); do bar+="░"; done
    echo "$bar"
}

BAR_WIDTH=16
CTX_BAR=$(make_bar "$CTX_USED"  "$BAR_WIDTH")
TOK_BAR=$(make_bar "$DAILY_PCT" "$BAR_WIDTH")

# Context bar color
if   [[ $CTX_USED -lt 50 ]]; then CTX_COLOR=$GREEN
elif [[ $CTX_USED -lt 80 ]]; then CTX_COLOR=$YELLOW
else                               CTX_COLOR=$RED
fi

# Daily usage bar color
if   [[ $DAILY_PCT -lt 50 ]]; then TOK_COLOR=$GREEN
elif [[ $DAILY_PCT -lt 80 ]]; then TOK_COLOR=$YELLOW
else                                TOK_COLOR=$RED
fi

# ---------------------------------------------------------------------------
# Line 1: folder  [on branch]  model
# ---------------------------------------------------------------------------
L1="${BOLD}${BLUE}${FOLDER}${R}"
[[ -n "$GIT_BRANCH" ]] && L1+="${WHITE}  ${DIM}on${R} ${CYAN}${GIT_BRANCH}${R}"
L1+="  ${WHITE}${MODEL}${R}"
printf '%b\n' "$L1"

# ---------------------------------------------------------------------------
# Line 2: Context: <bar> <pct>  |  Usage: <bar> <pct>
# ---------------------------------------------------------------------------
L2="${DIM}Context:${R} ${CTX_COLOR}${CTX_BAR} ${CTX_USED}%${R}  ${DIM}│${R}  ${DIM}Usage:${R} ${TOK_COLOR}${TOK_BAR} ${DAILY_PCT}%${R}"
printf '%b\n' "$L2"
