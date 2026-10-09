#!/bin/bash
# Claude Code status line — derived from ~/.bashrc PS1
# Format:
#   line1: user@host:cwd
#   line2: (git-branch) [model] [effort] [ctx: USED/TOTAL]
#   line3: [5h: NN% (in REMAIN)] [7d: NN% (in REMAIN)]

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Context usage (absolute tokens)
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // empty')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // empty')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // empty')

# Rate limits (Claude.ai サブスクリプション枠)
# rate_limits は初回API応答後にのみ渡され、各windowも独立に欠落しうる
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# ANSI color codes (matching PS1: bold green for user@host, bold blue for cwd)
GREEN='\033[01;32m'
BLUE='\033[01;34m'
YELLOW='\033[01;33m'
RED='\033[01;31m'
RESET='\033[00m'

# Format token count: 1234567 -> "1.2M", 43800 -> "43.8K"
format_tokens() {
    local n=$1
    if [ "$n" -ge 1000000 ] 2>/dev/null; then
        printf "%.1fM" "$(echo "scale=1; $n / 1000000" | bc)"
    elif [ "$n" -ge 1000 ] 2>/dev/null; then
        printf "%.1fK" "$(echo "scale=1; $n / 1000" | bc)"
    else
        printf "%d" "$n"
    fi
}

LIMIT_YELLOW_THRESHOLD=70
LIMIT_RED_THRESHOLD=90

# epoch秒 -> 残り時間 "3d4h" / "1h20m" / "12m"
format_remaining() {
    local target=$1 now diff d h m
    now=$(date +%s)
    diff=$(( target - now ))
    [ "$diff" -lt 0 ] && diff=0
    d=$(( diff / 86400 )); h=$(( (diff % 86400) / 3600 )); m=$(( (diff % 3600) / 60 ))
    if [ "$d" -gt 0 ]; then printf "%dd%dh" "$d" "$h"
    elif [ "$h" -gt 0 ]; then printf "%dh%dm" "$h" "$m"
    else printf "%dm" "$m"; fi
}

# "[5h: 42% (in 1h20m)]" を消費率に応じて着色
format_limit() {
    local label=$1 pct=$2 reset=$3 body int
    int=$(printf '%.0f' "$pct" 2>/dev/null) || int=0
    body="${label}: ${int}%"
    [ -n "$reset" ] && body="${body} (in $(format_remaining "$reset"))"
    if [ "$int" -ge "$LIMIT_RED_THRESHOLD" ] 2>/dev/null; then
        printf "${RED}[%s]${RESET}" "$body"
    elif [ "$int" -ge "$LIMIT_YELLOW_THRESHOLD" ] 2>/dev/null; then
        printf "${YELLOW}[%s]${RESET}" "$body"
    else
        printf "[%s]" "$body"
    fi
}

user_host="$(whoami)@$(hostname -s)"
dir="${cwd:-$(pwd)}"

# Line 1: user@host:cwd
printf "${GREEN}${user_host}${RESET}:${BLUE}${dir}${RESET}\n"

# Line 2: (git-branch) [model] [ctx: USED/TOTAL]
line2=""

# git branch (skip optional locks to avoid conflicts)
branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$dir" symbolic-ref --short HEAD 2>/dev/null)
if [ -n "$branch" ]; then
    line2="$(printf "${YELLOW}(${branch})${RESET}")"
fi

# model name
if [ -n "$model" ]; then
    [ -n "$line2" ] && line2="${line2} "
    line2="${line2}[${model}]"
fi

# effort level（工程ごとに /effort で切り替えるため、現在値を常時表示する）
if [ -n "$effort" ]; then
    [ -n "$line2" ] && line2="${line2} "
    line2="${line2}[effort: ${effort}]"
fi

# context usage: absolute tokens
# 通常コンテキスト(200K)基準の絶対しきい値で警告色を出す。1M有効時も同じ絶対値で発火させ、
# 200K相当を超えたら赤、その手前(160K)で黄に切り替える。
CTX_YELLOW_THRESHOLD=160000
CTX_RED_THRESHOLD=200000
if [ -n "$input_tokens" ] && [ -n "$ctx_size" ]; then
    used=$(( ${input_tokens:-0} + ${cache_create:-0} + ${cache_read:-0} ))
    used_fmt=$(format_tokens "$used")
    total_fmt=$(format_tokens "$ctx_size")
    [ -n "$line2" ] && line2="${line2} "
    if [ "$used" -ge "$CTX_RED_THRESHOLD" ] 2>/dev/null; then
        line2="${line2}$(printf "${RED}[ctx: ${used_fmt}/${total_fmt}]${RESET}")"
    elif [ "$used" -ge "$CTX_YELLOW_THRESHOLD" ] 2>/dev/null; then
        line2="${line2}$(printf "${YELLOW}[ctx: ${used_fmt}/${total_fmt}]${RESET}")"
    else
        line2="${line2}[ctx: ${used_fmt}/${total_fmt}]"
    fi
elif [ -n "$remaining" ]; then
    # Fallback: percentage display when absolute values are unavailable
    remaining_int=${remaining%.*}
    [ -n "$line2" ] && line2="${line2} "
    if [ "$remaining_int" -le 20 ] 2>/dev/null; then
        line2="${line2}$(printf "${RED}[ctx: ${remaining}%%]${RESET}")"
    else
        line2="${line2}[ctx: ${remaining}%]"
    fi
fi

# Line 3: プラン枠の消費率とリセットまでの残り時間。欠測しているwindowは項目ごと出さない。
line3=""
[ -n "$five_pct" ] && line3="$(format_limit "5h" "$five_pct" "$five_reset")"
if [ -n "$week_pct" ]; then
    [ -n "$line3" ] && line3="${line3} "
    line3="${line3}$(format_limit "7d" "$week_pct" "$week_reset")"
fi

printf "%s" "$line2"
[ -n "$line3" ] && printf "\n%s" "$line3"
