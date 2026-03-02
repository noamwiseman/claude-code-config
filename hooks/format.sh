#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

file_path=$(python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('tool_input', {}).get('file_path', ''))
" <<< "$input" 2>/dev/null) || true

[ -z "$file_path" ] && exit 0
[ ! -f "$file_path" ] && exit 0

ext="${file_path##*.}"
ext="${ext,,}"   # lowercase

case "$ext" in
  c|cpp|cxx|cc|h|hpp|hxx)
    command -v clang-format &>/dev/null && clang-format -i "$file_path" 2>/dev/null || true
    ;;
  py)
    command -v ruff &>/dev/null && ruff format "$file_path" 2>/dev/null || true
    ;;
esac

exit 0
