#!/usr/bin/env bash
# Claude Code Status Line
# Line 1: current folder | git branch | running model
# Line 2: context window bar | 5h usage bar + reset timer | 7d usage bar

# ---------------------------------------------------------------------------
# Read and parse JSON from stdin
# ---------------------------------------------------------------------------
INPUT=$(cat)

MODEL=$(    echo "$INPUT" | jq -r '.model.display_name // "Unknown"')
CWD=$(      echo "$INPUT" | jq -r '.cwd // ""')
CTX_USED=$( echo "$INPUT" | jq -r '(.context_window.used_percentage // 0) | floor')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')

PCT_5H=$(   echo "$INPUT" | jq -r '(.rate_limits.five_hour.used_percentage // 0) | floor')
RESET_5H=$( echo "$INPUT" | jq -r '.rate_limits.five_hour.resets_at // 0')
PCT_7D=$(   echo "$INPUT" | jq -r '(.rate_limits.seven_day.used_percentage // 0) | floor')

[[ $PCT_5H -gt 100 ]] && PCT_5H=100
[[ $PCT_7D  -gt 100 ]] && PCT_7D=100

# ---------------------------------------------------------------------------
# Line 1 data: folder name and git branch
# ---------------------------------------------------------------------------
FOLDER=$(basename "$CWD")
GIT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || true)
[[ -z "$GIT_BRANCH" ]] && GIT_BRANCH=$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null || true)

# ---------------------------------------------------------------------------
# 5h reset countdown: HH:MM
# ---------------------------------------------------------------------------
NOW=$(date +%s)
if [[ "$RESET_5H" -gt 0 ]]; then
    SECS_LEFT=$(( RESET_5H - NOW ))
    [[ $SECS_LEFT -lt 0 ]] && SECS_LEFT=0
    RESET_STR=$(printf "%02d:%02d" $(( SECS_LEFT / 3600 )) $(( (SECS_LEFT % 3600) / 60 )))
else
    RESET_STR="--:--"
fi

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

# ---------------------------------------------------------------------------
# Detect terminal width and scale bar width accordingly
# Fixed visible chars on line 2 (labels, %, separators, reset timer): ~47
# Three bars share the remaining space.
# ---------------------------------------------------------------------------
TERM_COLS=$(stty size </dev/tty 2>/dev/null | awk '{print $2}')
[[ -z "$TERM_COLS" ]] && TERM_COLS=$(tput cols 2>/dev/null)
[[ -z "$TERM_COLS" ]] && TERM_COLS="${COLUMNS:-80}"
BAR_WIDTH=$(( (TERM_COLS - 47) / 3 ))
[[ $BAR_WIDTH -lt 4  ]] && BAR_WIDTH=4
[[ $BAR_WIDTH -gt 20 ]] && BAR_WIDTH=20

CTX_BAR=$(make_bar "$CTX_USED" "$BAR_WIDTH")
BAR_5H=$(  make_bar "$PCT_5H"  "$BAR_WIDTH")
BAR_7D=$(  make_bar "$PCT_7D"  "$BAR_WIDTH")

bar_color() {
    local pct=$1
    if   [[ $pct -lt 50 ]]; then echo "$GREEN"
    elif [[ $pct -lt 80 ]]; then echo "$YELLOW"
    else                          echo "$RED"
    fi
}

CTX_COLOR=$(bar_color "$CTX_USED")
COLOR_5H=$( bar_color "$PCT_5H")
COLOR_7D=$( bar_color "$PCT_7D")

# ---------------------------------------------------------------------------
# Line 1: folder  [on branch]  model
# ---------------------------------------------------------------------------
L1="${BOLD}${BLUE}${FOLDER}${R}"
[[ -n "$GIT_BRANCH" ]] && L1+="${WHITE}  ${DIM}on${R} ${CYAN}${GIT_BRANCH}${R}"
L1+="  ${WHITE}${MODEL}${R}"
printf '%b\n' "$L1"

# ---------------------------------------------------------------------------
# Line 2: Ctx bar | 5h bar + reset timer | 7d bar
# ---------------------------------------------------------------------------
L2="${DIM}Ctx:${R} ${CTX_COLOR}${CTX_BAR} ${CTX_USED}%${R}"
L2+="  ${DIM}│${R}  ${DIM}5h:${R} ${COLOR_5H}${BAR_5H} ${PCT_5H}%${R}  ${DIM}⟳${R} ${WHITE}${RESET_STR}${R}"
L2+="  ${DIM}│${R}  ${DIM}7d:${R} ${COLOR_7D}${BAR_7D} ${PCT_7D}%${R}"
printf '%b\n' "$L2"
