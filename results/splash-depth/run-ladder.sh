#!/usr/bin/env bash
# Depth ladder for splash4 (LM Studio Splash, Qwen3.8-27B 4-bit + DFlash2).
# Same method as vacation-run/STRESS-GGUF.md Phase B: one real Claude Code session,
# turn N reads stress-corpus/fileN.md and must recall that file's planted designation.
# Metrics come from LM Studio's own "Done · input N · cached M · ..." log lines for the
# turn's byte range, not from client wall clock.
#
#   run-ladder.sh [max_turns]     (default 10)
set -uo pipefail

MAX="${1:-10}"
REPO=/Users/yash/Desktop/Programming/local-setup
CORPUS="$REPO/stress-corpus"
OUT="$(cd "$(dirname "$0")" && pwd)"
TURNS="$OUT/turns"; mkdir -p "$TURNS"
PROG="$OUT/progress.log"
SID="$(uuidgen | tr 'A-Z' 'a-z')"
WATCHDOG_S="${WATCHDOG_S:-2700}"   # 45 min per turn, as in the GGUF campaign

lms_log() { ls -t "$HOME"/.lmstudio/server-logs/*/*.log 2>/dev/null | head -1; }
panics() { ls /Library/Logs/DiagnosticReports/ 2>/dev/null | grep -c '^panic-full' || true; }
wired_gb() { vm_stat | awk '/wired down/ {gsub(/\./,"",$4); printf "%.2f", $4*16384/1073741824}'; }
free_pct() { memory_pressure 2>/dev/null | sed -n 's/.*free percentage: \([0-9]*\)%.*/\1/p'; }
lms_rss_gb() {  # biggest LM Studio-related process (the Splash worker holds the model)
  ps -axo rss=,command= | grep -i -E 'lm ?studio|lmstudio|splash' | grep -v grep \
    | sort -rn | head -1 | awk '{printf "%.2f", $1/1048576}'
}

{
  echo "SID=$SID  started $(date '+%F %T')  boottime=$(sysctl -n kern.boottime | sed 's/.*sec = \([0-9]*\).*/\1/')  panics=$(panics)"
  echo "idle wired=$(wired_gb)GB free=$(free_pct)%  $("$HOME"/.lmstudio/bin/lms ps 2>/dev/null | sed -n 3p)"
} | tee -a "$PROG"

fails=0
for n in $(seq 1 "$MAX"); do
  f="$CORPUS/file$n.md"
  title="$(head -1 "$f" | sed 's/^# //')"
  expect="$(grep -o 'permanent designation \*\*[A-Z-]*\*\*' "$f" | head -1 | sed 's/.*\*\*\([A-Z-]*\)\*\*/\1/')"
  q="Read the file stress-corpus/file$n.md completely — if the Read tool truncates it, keep reading with offsets until you have seen the whole file. Then answer: which designation identifies the sealed reference core of $title? Reply with just the designation."

  log="$(lms_log)"; start_line=$(wc -l <"$log" | tr -d ' ')
  t0=$(date +%s)
  if [[ $n -eq 1 ]]; then sess=(--session-id "$SID"); else sess=(--resume "$SID"); fi
  (cd "$REPO" && perl -e 'alarm shift; exec @ARGV' "$WATCHDOG_S" \
     ./scripts/qwen-code --dangerously-skip-permissions "${sess[@]}" -p "$q" \
     </dev/null >"$TURNS/B$n.out" 2>"$TURNS/B$n.err")
  rc=$?
  wall=$(( $(date +%s) - t0 ))
  log2="$(lms_log)"
  [[ "$log2" == "$log" ]] && tail -n +"$((start_line + 1))" "$log" >"$TURNS/B$n.lms.log" || cat "$log2" >"$TURNS/B$n.lms.log"

  reqs=$(grep -c 'Done · input' "$TURNS/B$n.lms.log" || true)
  errs=$(grep -c -i -E '\[ERROR\]|out of memory|OutOfMemory' "$TURNS/B$n.lms.log" || true)
  depth=$(grep -o 'Done · input [0-9,]*' "$TURNS/B$n.lms.log" | tr -d ',' | awk '{print $4}' | sort -n | tail -1)
  recall=no; grep -q "$expect" "$TURNS/B$n.out" && recall=yes
  status=OK; { [[ $rc -ne 0 ]] || [[ ! -s "$TURNS/B$n.out" ]] || [[ $recall == no ]]; } && status=FAIL

  {
    echo "TURN $n file$n status=$status rc=$rc wall=${wall}s reqs=$reqs errs=$errs depth=${depth:-0} recall=$recall expect=$expect got=\"$(tr '\n' ' ' <"$TURNS/B$n.out" | cut -c1-80)\" wired=$(wired_gb)GB free=$(free_pct)% lmsrss=$(lms_rss_gb)GB panics=$(panics)"
    grep 'Done · input' "$TURNS/B$n.lms.log" | sed 's/.*Done · /  /'
  } | tee -a "$PROG"

  if [[ $status == FAIL ]]; then fails=$((fails + 1)); else fails=0; fi
  if [[ $fails -ge 3 ]]; then echo "3 consecutive failures — ceiling reached" | tee -a "$PROG"; break; fi
  free=$(free_pct); if [[ -n "$free" && "$free" -lt 10 ]]; then echo "MEM RAIL: free ${free}% — stopping" | tee -a "$PROG"; break; fi
done
echo "finished $(date '+%F %T') panics=$(panics)" | tee -a "$PROG"
