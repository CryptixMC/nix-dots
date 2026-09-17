{ pkgs, ... }:

let
  # v2: still one shell-assertion-graded cell per invocation (never trust the
  # model's own claim — §7's history has fabricated success and a Summon
  # overwrite the primary's own verification missed), but now parameterized
  # over TASK_SHAPE and able to point at an isolated scratch Ollama instance
  # for CPU-only testing, so a driving matrix script can iterate model x
  # dock-state x thinking-on/off x task-shape without touching the live
  # ollama.service. Resumable via the same label-skip logic as v1.
  gooseBench = pkgs.writeShellScriptBin "goose-bench" ''
    set -uo pipefail

    MODEL="''${1:?usage: goose-bench MODEL [PROVIDER] [LABEL] [TASK_SHAPE] [OLLAMA_HOST_OVERRIDE]}"
    PROVIDER="''${2:-ollama}"
    LABEL="''${3:-$MODEL}"
    TASK_SHAPE="''${4:-append-naive}"
    HOST_OVERRIDE="''${5:-}"

    RESULTS="''${GOOSE_BENCH_RESULTS:-$HOME/.local/share/goose-bench/results.jsonl}"
    mkdir -p "$(dirname "$RESULTS")"

    if [ -f "$RESULTS" ] && grep -q "\"label\":\"$LABEL\"" "$RESULTS" 2>/dev/null; then
      echo "[goose-bench] $LABEL already has a result, skipping (delete its line from $RESULTS to re-run)" >&2
      exit 0
    fi

    SCRATCH=$(mktemp -d)
    trap 'rm -rf "$SCRATCH"' EXIT

    # append-naive: deliberately gives NO anti-overwrite guardrail in the
    # instruction (unlike the original v1 task) -- this is the shape that
    # actually caught qwen3:8b choosing a full-file write over an append
    # earlier this session. read-report: pure read, zero mutation expected;
    # graded from the model's own answer text, not a file. edit-verify:
    # a real two-step task (edit, then the model is told to self-check).
    case "$TASK_SHAPE" in
      append-naive)
        printf 'line one\nline two\nline three\n' > "$SCRATCH/target.txt"
        TASK_TEXT='Add a new line to target.txt containing the text line four.'
        ;;
      read-report)
        printf '[package]\nname = "probe"\nversion = "9.9.9"\n' > "$SCRATCH/Cargo.toml"
        TASK_TEXT='Read Cargo.toml in this directory and tell me the exact version string. Only report the value, do not edit anything.'
        ;;
      edit-verify)
        printf 'value = 1\n' > "$SCRATCH/config.txt"
        TASK_TEXT='Change config.txt so that value equals 2 instead of 1. After editing, read the file back to confirm your change landed correctly.'
        ;;
      *)
        echo "[goose-bench] unknown TASK_SHAPE: $TASK_SHAPE (expected append-naive, read-report, or edit-verify)" >&2
        exit 1
        ;;
    esac

    export GOOSE_PATH_ROOT="$SCRATCH/goose-root"
    mkdir -p "$GOOSE_PATH_ROOT"
    if [ -n "$HOST_OVERRIDE" ]; then
      export OLLAMA_HOST="$HOST_OVERRIDE"
    fi

    START=$(date +%s)
    (
      cd "$SCRATCH"
      ${pkgs.goose-cli}/bin/goose run \
        --text "$TASK_TEXT" \
        --no-session \
        --stats \
        --provider "$PROVIDER" \
        --model "$MODEL"
    ) > "$SCRATCH/run.log" 2>&1
    END=$(date +%s)
    WALL=$((END - START))

    PASS=false
    case "$TASK_SHAPE" in
      append-naive)
        if grep -q "line four" "$SCRATCH/target.txt" 2>/dev/null \
          && grep -q "line one" "$SCRATCH/target.txt" 2>/dev/null \
          && grep -q "line two" "$SCRATCH/target.txt" 2>/dev/null \
          && grep -q "line three" "$SCRATCH/target.txt" 2>/dev/null; then
          PASS=true
        fi
        ;;
      read-report)
        # Graded from the transcript, not a file -- this task has nothing to
        # mutate. A model that also edited something anyway still fails if
        # it never states the real value.
        if grep -q "9\.9\.9" "$SCRATCH/run.log" 2>/dev/null; then
          PASS=true
        fi
        ;;
      edit-verify)
        if grep -q "value = 2" "$SCRATCH/config.txt" 2>/dev/null; then
          PASS=true
        fi
        ;;
    esac

    LOG=$(find "$GOOSE_PATH_ROOT/state/logs/cli" -name '*.log' 2>/dev/null | head -1)
    TOKENS=null
    SHIM_FAIL=0
    TRUNCATED=0
    EMPTY_RESP=0
    if [ -n "$LOG" ] && [ -f "$LOG" ]; then
      FOUND_TOKENS=$(grep -oE '"total_tokens":[0-9]+' "$LOG" | tail -1 | grep -oE '[0-9]+')
      [ -n "$FOUND_TOKENS" ] && TOKENS="$FOUND_TOKENS"
      # grep -c always prints a count (0 or more), but exits 1 when the
      # count is 0 — an `|| echo 0` fallback here would double the output
      # into two lines ("0\n0") and corrupt the JSON below. Redirect
      # stderr only; let a real zero count stand on its own.
      SHIM_FAIL=$(grep -c "Toolshim augmentation failed" "$LOG" 2>/dev/null)
      TRUNCATED=$(grep -c "reached its output token limit" "$LOG" 2>/dev/null)
      EMPTY_RESP=$(grep -c "empty response" "$LOG" 2>/dev/null)
    fi

    printf '{"label":"%s","model":"%s","provider":"%s","task_shape":"%s","think":"%s","pass":%s,"wall_seconds":%s,"tokens":%s,"toolshim_failures":%s,"truncated":%s,"empty_responses":%s,"timestamp":"%s"}\n' \
      "$LABEL" "$MODEL" "$PROVIDER" "$TASK_SHAPE" "''${GOOSE_LOCAL_ENABLE_THINKING:-unset}" "$PASS" "$WALL" "$TOKENS" "$SHIM_FAIL" "$TRUNCATED" "$EMPTY_RESP" "$(date -Iseconds)" \
      >> "$RESULTS"

    echo "[goose-bench] $LABEL ($TASK_SHAPE): pass=$PASS wall=''${WALL}s tokens=$TOKENS -> $RESULTS"
  '';

  # Drives goose-bench across model x task-shape x thinking-on/off for a
  # given provider/host, i.e. one full sweep for either "docked" (live
  # ollama.service) or an already-running isolated scratch instance passed
  # via --host. Does NOT start/stop Ollama itself -- CPU-only cells need an
  # isolated `HIP_VISIBLE_DEVICES="" ollama serve` on an alternate port
  # started by the caller first (see TODO.md's documented pattern: track the
  # PID, kill it in a trap, never touch the live service). This script only
  # knows how to point goose-bench at whatever host it's given.
  gooseBenchMatrix = pkgs.writeShellScriptBin "goose-bench-matrix" ''
    set -uo pipefail

    HOST=""
    LABEL_PREFIX="docked"
    MODELS=""
    SHAPES="append-naive read-report edit-verify"
    THINK_MODES="true false"

    while [ $# -gt 0 ]; do
      case "$1" in
        --host) HOST="$2"; shift 2 ;;
        --label-prefix) LABEL_PREFIX="$2"; shift 2 ;;
        --models) MODELS="$2"; shift 2 ;;
        --shapes) SHAPES="$2"; shift 2 ;;
        --think-modes) THINK_MODES="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
      esac
    done

    if [ -z "$MODELS" ]; then
      echo "usage: goose-bench-matrix --models 'model1 model2' [--host HOST:PORT] [--label-prefix docked] [--shapes '...'] [--think-modes '...']" >&2
      exit 1
    fi

    for MODEL in $MODELS; do
      for SHAPE in $SHAPES; do
        for THINK in $THINK_MODES; do
          SAFE_MODEL=$(echo "$MODEL" | tr ':/' '--')
          LABEL="''${LABEL_PREFIX}-''${SAFE_MODEL}-''${SHAPE}-think''${THINK}"
          echo "[goose-bench-matrix] running $LABEL"
          GOOSE_LOCAL_ENABLE_THINKING="$THINK" ${gooseBench}/bin/goose-bench \
            "$MODEL" ollama "$LABEL" "$SHAPE" "$HOST"
        done
      done
    done
  '';
in
{
  home.packages = [
    gooseBench
    gooseBenchMatrix
  ];
}
