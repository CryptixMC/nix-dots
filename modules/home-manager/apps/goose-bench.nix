{ pkgs, ... }:

let
  # Lean v1: a single-cell benchmark runner, not the full model x profile x
  # dock-state x toolshim matrix from the plan doc — that's follow-on work
  # built on top of this primitive. One cell = one (model, provider) pair
  # run against a fixed, minimal task in a disposable GOOSE_PATH_ROOT
  # sandbox, graded by reading the actual file back (never by trusting the
  # model's own claim of success — §7's own history has fabricated
  # `py_compile` success and a Summon overwrite the primary's own `tail`
  # verification missed).
  #
  # Resumable: skips a label already present in the results file, so
  # re-running the same invocation after a partial matrix doesn't redo
  # completed cells. Delete the matching line from the results file to
  # force a specific cell to re-run.
  gooseBench = pkgs.writeShellScriptBin "goose-bench" ''
    set -uo pipefail

    MODEL="''${1:?usage: goose-bench MODEL [PROVIDER] [LABEL]}"
    PROVIDER="''${2:-ollama}"
    LABEL="''${3:-$MODEL}"

    RESULTS="''${GOOSE_BENCH_RESULTS:-$HOME/.local/share/goose-bench/results.jsonl}"
    mkdir -p "$(dirname "$RESULTS")"

    if [ -f "$RESULTS" ] && grep -q "\"label\":\"$LABEL\"" "$RESULTS" 2>/dev/null; then
      echo "[goose-bench] $LABEL already has a result, skipping (delete its line from $RESULTS to re-run)" >&2
      exit 0
    fi

    SCRATCH=$(mktemp -d)
    trap 'rm -rf "$SCRATCH"' EXIT

    printf 'line one\nvalue is before\nline three\n' > "$SCRATCH/target.txt"

    export GOOSE_PATH_ROOT="$SCRATCH/goose-root"
    mkdir -p "$GOOSE_PATH_ROOT"

    START=$(date +%s)
    (
      cd "$SCRATCH"
      ${pkgs.goose-cli}/bin/goose run \
        --text 'Open target.txt and change the line that says value is before so that it instead says value is after. Do not change anything else in the file.' \
        --no-session \
        --stats \
        --provider "$PROVIDER" \
        --model "$MODEL"
    ) > "$SCRATCH/run.log" 2>&1
    END=$(date +%s)
    WALL=$((END - START))

    PASS=false
    if grep -q "value is after" "$SCRATCH/target.txt" 2>/dev/null \
      && ! grep -q "value is before" "$SCRATCH/target.txt" 2>/dev/null; then
      PASS=true
    fi

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

    printf '{"label":"%s","model":"%s","provider":"%s","pass":%s,"wall_seconds":%s,"tokens":%s,"toolshim_failures":%s,"truncated":%s,"empty_responses":%s,"timestamp":"%s"}\n' \
      "$LABEL" "$MODEL" "$PROVIDER" "$PASS" "$WALL" "$TOKENS" "$SHIM_FAIL" "$TRUNCATED" "$EMPTY_RESP" "$(date -Iseconds)" \
      >> "$RESULTS"

    echo "[goose-bench] $LABEL: pass=$PASS wall=''${WALL}s tokens=$TOKENS -> $RESULTS"
  '';
in
{
  home.packages = [
    gooseBench
  ];
}
