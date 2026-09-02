#!/bin/sh
set -u

: "${RUN_ID:?RUN_ID is required}"
: "${LEAF:?LEAF is required}"
: "${REMOTE_ROOT:?REMOTE_ROOT is required}"
: "${VPIPE_BIN:?VPIPE_BIN is required}"

PARENT_RUN_ID=${PARENT_RUN_ID:-}
MODEL_SENTINEL=${MODEL_SENTINEL:-}
FREE_PERCENT_FLOOR=${FREE_PERCENT_FLOOR:-5}
SWAP_LIMIT_MB=${SWAP_LIMIT_MB:-6144}
MEMORY_SAMPLE_SECONDS=${MEMORY_SAMPLE_SECONDS:-10}
MEMORY_CRITICAL_SAMPLES=${MEMORY_CRITICAL_SAMPLES:-3}

PIPELINE_ROOT="$REMOTE_ROOT/pipelines/$LEAF"
OUTPUT_ROOT="$REMOTE_ROOT/output/$LEAF"
LOG_ROOT="$REMOTE_ROOT/logs/$LEAF"
STATE_ROOT="$REMOTE_ROOT/state/$RUN_ID"
PARENT_STATE_ROOT="$REMOTE_ROOT/state/$PARENT_RUN_ID"
QUEUE_FILE=${QUEUE_FILE:-"$STATE_ROOT/queue.tsv"}
CHECKSUM_FILE=${CHECKSUM_FILE:-"$STATE_ROOT/remote-checksums.sha256"}
PROGRESS_TSV="$STATE_ROOT/progress.tsv"
LOCK_ROOT="$REMOTE_ROOT/state/vpipe-exclusive.lock"

timestamp() { date '+%Y-%m-%dT%H:%M:%S%z'; }

safe_token() {
  case "$1" in
    ""|*[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

safe_unsigned_integer() {
  case "$1" in
    ""|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

case "$REMOTE_ROOT" in
  /*) ;;
  *) printf '%s\n' "REMOTE_ROOT must be absolute" >&2; exit 64 ;;
esac
case "$REMOTE_ROOT" in
  *"'"*|*"\""*|*"\t"*|*"\n"*) printf '%s\n' "REMOTE_ROOT contains unsupported characters" >&2; exit 64 ;;
esac
safe_token "$RUN_ID" || { printf '%s\n' "unsafe RUN_ID" >&2; exit 64; }
safe_token "$LEAF" || { printf '%s\n' "unsafe LEAF" >&2; exit 64; }
if [ -n "$PARENT_RUN_ID" ]; then
  safe_token "$PARENT_RUN_ID" || { printf '%s\n' "unsafe PARENT_RUN_ID" >&2; exit 64; }
fi
for number in "$FREE_PERCENT_FLOOR" "$SWAP_LIMIT_MB" "$MEMORY_SAMPLE_SECONDS" "$MEMORY_CRITICAL_SAMPLES"; do
  safe_unsigned_integer "$number" || { printf '%s\n' "memory thresholds must be unsigned integers" >&2; exit 64; }
done

mkdir -p "$OUTPUT_ROOT" "$LOG_ROOT" "$STATE_ROOT"
cd "$REMOTE_ROOT" || exit 1

record() {
  state="$1"
  detail="$2"
  printf '%s\t%s\t%s\n' "$(timestamp)" "$state" "$detail" >>"$PROGRESS_TSV"
  printf '%s %s %s\n' "$(timestamp)" "$state" "$detail"
}

validate_output() {
  candidate="$1"
  [ -s "$candidate" ] || return 1
  size=$(stat -f '%z' "$candidate" 2>/dev/null || printf '0')
  [ "$size" -ge 100000 ] || return 1
  file "$candidate" | grep -Eq 'ISO Media|MP4|QuickTime' || return 1
  python3 - "$candidate" <<'PY'
import os
import struct
import sys

path = sys.argv[1]
size = os.path.getsize(path)
atoms = set()
with open(path, "rb") as handle:
    offset = 0
    while offset + 8 <= size:
        handle.seek(offset)
        header = handle.read(8)
        if len(header) != 8:
            break
        atom_size, atom_type = struct.unpack(">I4s", header)
        atom_type = atom_type.decode("latin-1")
        header_size = 8
        if atom_size == 1:
            extended = handle.read(8)
            if len(extended) != 8:
                raise SystemExit(2)
            atom_size = struct.unpack(">Q", extended)[0]
            header_size = 16
        elif atom_size == 0:
            atom_size = size - offset
        if atom_size < header_size or offset + atom_size > size:
            raise SystemExit(3)
        atoms.add(atom_type)
        offset += atom_size
required = {"ftyp", "moov", "mdat"}
raise SystemExit(0 if required.issubset(atoms) else 4)
PY
}

fail_controller() {
  code="$1"
  detail="$2"
  printf '%s\n' "failed" >"$STATE_ROOT/status.txt"
  record CONTROLLER_FAILED "$detail"
  exit "$code"
}

release_lock() {
  if [ -f "$LOCK_ROOT/owner.pid" ] && [ "$(cat "$LOCK_ROOT/owner.pid" 2>/dev/null)" = "$$" ]; then
    rm -f "$LOCK_ROOT/owner.pid" "$LOCK_ROOT/run-id.txt"
    rmdir "$LOCK_ROOT" 2>/dev/null || true
  fi
}

acquire_lock() {
  printf '%s\n' "waiting_for_vpipe_lock" >"$STATE_ROOT/status.txt"
  record WAITING_FOR_LOCK "lock=$LOCK_ROOT"
  while ! mkdir "$LOCK_ROOT" 2>/dev/null; do
    owner_pid=$(cat "$LOCK_ROOT/owner.pid" 2>/dev/null || printf '')
    if [ -n "$owner_pid" ] && safe_unsigned_integer "$owner_pid" && ! kill -0 "$owner_pid" 2>/dev/null; then
      rm -f "$LOCK_ROOT/owner.pid" "$LOCK_ROOT/run-id.txt"
      rmdir "$LOCK_ROOT" 2>/dev/null || true
      continue
    fi
    sleep 30
  done
  printf '%s\n' "$$" >"$LOCK_ROOT/owner.pid"
  printf '%s\n' "$RUN_ID" >"$LOCK_ROOT/run-id.txt"
  trap 'release_lock' 0
  trap 'release_lock; exit 129' HUP
  trap 'release_lock; exit 130' INT
  trap 'release_lock; exit 143' TERM
  record LOCK_ACQUIRED "pid=$$"
}

sample_memory() {
  vpipe_pid="$1"
  telemetry="$2"
  consecutive_critical=0
  while kill -0 "$vpipe_pid" 2>/dev/null; do
    if command -v memory_pressure >/dev/null 2>&1; then
      free_percent=$(memory_pressure -Q 2>/dev/null | awk '/System-wide memory free percentage:/ {gsub(/%/, "", $NF); print $NF; exit}')
    else
      free_percent=-1
    fi
    if command -v sysctl >/dev/null 2>&1; then
      swap_line=$(sysctl vm.swapusage 2>/dev/null | tr '\n' ' ')
    else
      swap_line="swap_unavailable"
    fi
    rss_kb=$(ps -o rss= -p "$vpipe_pid" 2>/dev/null | awk '{print $1}')
    [ -n "$free_percent" ] || free_percent=-1
    [ -n "$rss_kb" ] || rss_kb=0
    printf '%s\tpid=%s\tfree_percent=%s\trss_kb=%s\t%s\n' "$(timestamp)" "$vpipe_pid" "$free_percent" "$rss_kb" "$swap_line" >>"$telemetry"

    swap_token=$(printf '%s\n' "$swap_line" | awk -F'used = ' '{print $2}' | awk '{print $1}')
    swap_number=$(printf '%s' "$swap_token" | sed 's/[^0-9.]//g')
    swap_unit=$(printf '%s' "$swap_token" | sed 's/[0-9.]//g')
    swap_mb=0
    case "$swap_unit" in
      G) swap_mb=$(awk -v value="$swap_number" 'BEGIN {printf "%d", value * 1024}') ;;
      M) swap_mb=$(awk -v value="$swap_number" 'BEGIN {printf "%d", value}') ;;
    esac

    memory_is_critical=false
    if [ "$FREE_PERCENT_FLOOR" -gt 0 ] && [ "$free_percent" -ge 0 ] && [ "$free_percent" -le "$FREE_PERCENT_FLOOR" ]; then
      memory_is_critical=true
    fi
    if [ "$SWAP_LIMIT_MB" -gt 0 ] && [ "$swap_mb" -ge "$SWAP_LIMIT_MB" ]; then
      memory_is_critical=true
    fi
    if [ "$memory_is_critical" = true ]; then
      consecutive_critical=$((consecutive_critical + 1))
    else
      consecutive_critical=0
    fi
    if [ "$consecutive_critical" -ge "$MEMORY_CRITICAL_SAMPLES" ]; then
      printf '%s\n' "free_percent=$free_percent swap_mb=$swap_mb" >"$STATE_ROOT/memory-critical.txt"
      kill -TERM "$vpipe_pid" 2>/dev/null || true
      return 0
    fi
    sleep "$MEMORY_SAMPLE_SECONDS"
  done
}

run_one() {
  order="$1"
  slug="$2"
  seed="$3"
  label="$4"
  pipeline="$PIPELINE_ROOT/$slug.vpipeline"
  output="$OUTPUT_ROOT/$slug.mp4"
  log="$LOG_ROOT/$slug.log"
  telemetry="$LOG_ROOT/$slug.memory.tsv"

  safe_token "$slug" || fail_controller 20 "order=$order reason=unsafe_slug"
  safe_unsigned_integer "$seed" || fail_controller 20 "slug=$slug reason=unsafe_seed"
  [ -f "$pipeline" ] || fail_controller 20 "slug=$slug reason=pipeline_missing"
  if validate_output "$output"; then
    size=$(stat -f '%z' "$output")
    digest=$(shasum -a 256 "$output" | awk '{print toupper($1)}')
    record SKIPPED_VALID "order=$order slug=$slug seed=$seed label=$label bytes=$size sha256=$digest"
    return 0
  fi

  rm -f "$STATE_ROOT/memory-critical.txt"
  printf '%s\n' "running:$slug" >"$STATE_ROOT/status.txt"
  record STARTED "order=$order slug=$slug seed=$seed label=$label"
  started=$(date '+%s')
  "$VPIPE_BIN" --launch "$pipeline" >"$log" 2>&1 &
  vpipe_pid=$!
  sample_memory "$vpipe_pid" "$telemetry" &
  monitor_pid=$!
  wait "$vpipe_pid"
  status=$?
  wait "$monitor_pid" 2>/dev/null || true
  elapsed=$(($(date '+%s') - started))

  if [ -f "$STATE_ROOT/memory-critical.txt" ]; then
    detail=$(cat "$STATE_ROOT/memory-critical.txt")
    fail_controller 22 "slug=$slug seed=$seed reason=memory_guard seconds=$elapsed $detail"
  fi
  if [ "$status" -eq 0 ] && validate_output "$output"; then
    size=$(stat -f '%z' "$output")
    digest=$(shasum -a 256 "$output" | awk '{print toupper($1)}')
    record COMPLETED "order=$order slug=$slug seed=$seed label=$label seconds=$elapsed bytes=$size sha256=$digest"
    return 0
  fi
  tail -n 100 "$log" || true
  fail_controller 21 "slug=$slug seed=$seed status=$status seconds=$elapsed log=$log"
}

[ -x "$VPIPE_BIN" ] || fail_controller 2 "reason=vpipe_missing"
if [ -n "$MODEL_SENTINEL" ] && [ ! -f "$MODEL_SENTINEL" ]; then
  fail_controller 3 "reason=model_sentinel_missing"
fi
[ -f "$QUEUE_FILE" ] || fail_controller 4 "reason=queue_missing"
[ -f "$CHECKSUM_FILE" ] || fail_controller 4 "reason=checksum_manifest_missing"

tab=$(printf '\t')
if ! awk -F "$tab" '
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  NF != 4 { exit 2 }
  $1 !~ /^[0-9]+$/ || $2 !~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/ || $3 !~ /^[0-9]+$/ { exit 3 }
  seen[$2]++ { exit 4 }
  { count++ }
  END { if (count < 1 || count > 6) exit 5 }
' "$QUEUE_FILE"; then
  fail_controller 4 "reason=queue_contract_failed"
fi
if ! shasum -a 256 -c "$CHECKSUM_FILE" >"$STATE_ROOT/preflight-checksums.log" 2>&1; then
  tail -n 100 "$STATE_ROOT/preflight-checksums.log" || true
  fail_controller 5 "reason=checksum_preflight_failed"
fi

printf '%s\n' "$$" >"$STATE_ROOT/controller.pid"
printf '%s\n' "$(timestamp)" >"$STATE_ROOT/started-at.txt"
printf '%s\n' "waiting_for_parent_run" >"$STATE_ROOT/status.txt"
record QUEUE_STARTED "pid=$$ parent=${PARENT_RUN_ID:-none}"

if [ -n "$PARENT_RUN_ID" ]; then
  last_parent_status=""
  while :; do
    parent_status=$(cat "$PARENT_STATE_ROOT/status.txt" 2>/dev/null || printf 'missing')
    parent_status=$(printf '%s' "$parent_status" | tail -n 1)
    if [ "$parent_status" != "$last_parent_status" ]; then
      record PARENT_STATUS "parent=$PARENT_RUN_ID status=$parent_status"
      last_parent_status="$parent_status"
    fi
    case "$parent_status" in
      complete) record PARENT_COMPLETED "parent=$PARENT_RUN_ID"; break ;;
      failed) fail_controller 10 "reason=parent_failed parent=$PARENT_RUN_ID" ;;
    esac
    sleep 30
  done
fi

acquire_lock
printf '%s\n' "waiting_for_vpipe_slot" >"$STATE_ROOT/status.txt"
record WAITING_FOR_SLOT "reason=exclusive_vpipe"
while pgrep -f "$VPIPE_BIN --launch" >/dev/null 2>&1; do sleep 30; done

job_count=0
expected_order=1
while IFS="$tab" read -r order slug seed label; do
  case "$order" in
    ""|\#*) continue ;;
  esac
  [ "$order" -eq "$expected_order" ] || fail_controller 20 "reason=unexpected_order expected=$expected_order actual=$order"
  run_one "$order" "$slug" "$seed" "$label"
  job_count=$((job_count + 1))
  expected_order=$((expected_order + 1))
done <"$QUEUE_FILE"

printf '%s\n' "$(timestamp)" >"$STATE_ROOT/finished-at.txt"
printf '%s\n' "complete" >"$STATE_ROOT/status.txt"
record BATCH_COMPLETED "jobs=$job_count"
exit 0
