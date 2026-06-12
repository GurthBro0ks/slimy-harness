#!/usr/bin/env bash
# Local Model Routing Phase 5B - qwen2.5:1.5b recovery benchmark tooling.
#
# Default mode is a manual real benchmark for a future NUC1 operator run.
# Recovery/operator QA should use --defer-model-run, which writes the full
# artifact set without calling Ollama, pulling models, or claiming a
# performance verdict.
set -euo pipefail

MODEL="qwen2.5:1.5b"
PROOF_DIR=""
DEFER_MODEL_RUN="no"
DEFER_REASON=""
TIMEOUT_SECONDS=10
STRICT_PROMPT_COUNT=8

usage() {
  cat <<'EOF'
Usage: bash benchmark-qwen25-tiny.sh --proof-dir DIR [options]

Required:
  --proof-dir DIR             Directory to write benchmark proof artifacts.

Options:
  --defer-model-run           Write all artifacts without calling Ollama.
  --defer-reason TEXT         Reason recorded when --defer-model-run is used.
  --timeout-seconds N         Per-prompt timeout for future real mode (default: 10).
  -h, --help                  Show this help.

Artifacts written into --proof-dir:
  ollama-command.txt
  ollama-list.txt
  model-presence.txt
  benchmark-output.txt
  benchmark-summary.json
  benchmark-summary.txt
  benchmark-subset-summary.txt
  artifact-presence.txt

Deferred mode is for recovery/operator QA only. It does not call Ollama,
does not pull models, does not claim latency, does not claim pass counts,
and records QWEN25_RECOMMENDATION=none.
EOF
}

json_escape() {
  python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))'
}

refuse_unsafe_proof_dir() {
  case "$PROOF_DIR" in
    /|/etc|/etc/*|/bin|/bin/*|/sbin|/sbin/*|/usr|/usr/*|/var|/var/*|/root|/root/*|/boot|/boot/*)
      printf 'ERROR: refusing unsafe --proof-dir: %s\n' "$PROOF_DIR" >&2
      exit 2
      ;;
  esac
}

write_artifact_presence() {
  local missing=0
  local artifact

  {
    for artifact in \
      ollama-command.txt \
      ollama-list.txt \
      model-presence.txt \
      benchmark-output.txt \
      benchmark-summary.json \
      benchmark-summary.txt \
      benchmark-subset-summary.txt \
      artifact-presence.txt
    do
      if [[ -f "$PROOF_DIR/$artifact" ]]; then
        printf '%s=present\n' "$artifact"
      else
        printf '%s=missing\n' "$artifact"
        missing=1
      fi
    done
    if [[ "$missing" -eq 0 ]]; then
      printf 'ALL_REQUIRED_ARTIFACTS_PRESENT=yes\n'
    else
      printf 'ALL_REQUIRED_ARTIFACTS_PRESENT=no\n'
    fi
  } > "$PROOF_DIR/artifact-presence.txt"
}

write_deferred_artifacts() {
  local reason_json
  reason_json="$(printf '%s' "$DEFER_REASON" | json_escape)"

  cat > "$PROOF_DIR/ollama-command.txt" <<EOF
PHASE=nuc1-local-model-routing-phase5b-clean-reconcile
MODE=deferred
OLLAMA_CALLED=no
OLLAMA_CALL_SCOPE=none
MODELS_PULLED=no
OLLAMA_PULL_ATTEMPTED=no
LIVE_ROUTING_CHANGED=no
COMMAND_NOT_RUN=timeout ${TIMEOUT_SECONDS}s ollama run ${MODEL}
DEFER_REASON=${DEFER_REASON}
EOF

  cat > "$PROOF_DIR/ollama-list.txt" <<EOF
PHASE=nuc1-local-model-routing-phase5b-clean-reconcile
MODE=deferred
OLLAMA_LIST_RUN=no
OLLAMA_CALLED=no
CONTENT=Deferred recovery artifact; model inventory must be checked only during an operator-approved NUC1 real benchmark.
DEFER_REASON=${DEFER_REASON}
EOF

  cat > "$PROOF_DIR/model-presence.txt" <<EOF
PHASE=nuc1-local-model-routing-phase5b-clean-reconcile
MODE=deferred
MODEL=${MODEL}
OLLAMA_PRESENT=not_checked
QWEN25_MODEL_PRESENT=not_checked
MODELS_PULLED=no
OLLAMA_PULL_ATTEMPTED=no
DEFER_REASON=${DEFER_REASON}
EOF

  cat > "$PROOF_DIR/benchmark-output.txt" <<EOF
PHASE=nuc1-local-model-routing-phase5b-clean-reconcile
MODE=deferred
RESULT=WARN
BENCHMARK_RUN=no
BENCHMARK_VERDICT=deferred_until_nuc1_online
STRICT_PROMPTS_RUN=no
STRICT_PROMPT_COUNT=${STRICT_PROMPT_COUNT}
QWEN25_RECOMMENDATION=none
QWEN25_DECISION=do_not_wire_into_harness
NO_LATENCY_CLAIM=yes
NO_PASS_COUNT_CLAIM=yes
DEFER_REASON=${DEFER_REASON}
EOF

  cat > "$PROOF_DIR/benchmark-summary.json" <<EOF
{
  "phase": "nuc1-local-model-routing-phase5b-clean-reconcile",
  "result": "WARN",
  "mode": "deferred",
  "model": "${MODEL}",
  "benchmark_run": "no",
  "benchmark_verdict": "deferred_until_nuc1_online",
  "qwen25_recommendation": "none",
  "qwen25_decision": "do_not_wire_into_harness",
  "models_pulled": "no",
  "ollama_pull_attempted": "no",
  "live_routing_changed": "no",
  "ollama_called": "no",
  "ollama_call_scope": "none",
  "ollama_present": "not_checked",
  "qwen25_model_present": "not_checked",
  "strict_prompt_count": ${STRICT_PROMPT_COUNT},
  "strict_prompts_run": "no",
  "latency_claimed": "no",
  "pass_count_claimed": "no",
  "forensic_phase5_result": "WARN",
  "forensic_phase5_direct_benchmark_proof_recovered": "no",
  "defer_reason": ${reason_json}
}
EOF

  cat > "$PROOF_DIR/benchmark-summary.txt" <<EOF
PHASE=nuc1-local-model-routing-phase5b-clean-reconcile
RESULT=WARN
MODE=deferred
MODEL=${MODEL}
BENCHMARK_RUN=no
BENCHMARK_VERDICT=deferred_until_nuc1_online
QWEN25_RECOMMENDATION=none
QWEN25_DECISION=do_not_wire_into_harness
MODELS_PULLED=no
OLLAMA_PULL_ATTEMPTED=no
LIVE_ROUTING_CHANGED=no
OLLAMA_CALLED=no
OLLAMA_CALL_SCOPE=none
FORENSIC_PHASE5_RESULT=WARN
FORENSIC_PHASE5_PM_RECORDED_BENCHMARK_VERDICT=inconclusive
FORENSIC_PHASE5_DIRECT_BENCHMARK_PROOF_RECOVERED=no
DEFER_REASON=${DEFER_REASON}
EOF

  cat > "$PROOF_DIR/benchmark-subset-summary.txt" <<EOF
STRICT_PROMPT_SET=future_nuc1_only
STRICT_PROMPTS_RUN=no
STRICT_PROMPT_COUNT=${STRICT_PROMPT_COUNT}
route_hint_allow=deferred
route_hint_deny_code_generation=deferred
dirty_state_clean=deferred
dirty_state_dirty=deferred
risk_label_secrets=deferred
warn_fail_detect_pass=deferred
warn_fail_detect_warn=deferred
short_status_label_warn=deferred
EOF
}

run_prompt() {
  local key="$1"
  local expected="$2"
  local prompt="$3"
  local output_file="$PROOF_DIR/${key}.out"
  local result="FAIL"
  local output=""

  if output="$(printf '%s\n' "$prompt" | timeout "${TIMEOUT_SECONDS}s" ollama run "$MODEL" 2>&1)"; then
    printf '%s\n' "$output" > "$output_file"
    if [[ "$(printf '%s' "$output" | tr -d '\r' | head -n1 | awk '{$1=$1; print}')" == "$expected" ]]; then
      result="PASS"
    fi
  else
    printf '%s\n' "$output" > "$output_file"
    result="TIMEOUT_OR_ERROR"
  fi

  printf '%s=%s expected=%s output_file=%s\n' "$key" "$result" "$expected" "$output_file"
}

write_real_mode_missing_ollama() {
  cat > "$PROOF_DIR/model-presence.txt" <<EOF
PHASE=local-model-routing-phase5b-strict-benchmark
MODE=real
MODEL=${MODEL}
OLLAMA_PRESENT=no
QWEN25_MODEL_PRESENT=no
MODELS_PULLED=no
OLLAMA_PULL_ATTEMPTED=no
EOF

  cat > "$PROOF_DIR/benchmark-output.txt" <<'EOF'
PHASE=local-model-routing-phase5b-strict-benchmark
RESULT=WARN
BENCHMARK_RUN=no
BENCHMARK_VERDICT=ollama_unavailable
QWEN25_RECOMMENDATION=none
QWEN25_DECISION=do_not_wire_into_harness
EOF

  cat > "$PROOF_DIR/benchmark-subset-summary.txt" <<EOF
STRICT_PROMPTS_RUN=no
STRICT_PROMPT_COUNT=${STRICT_PROMPT_COUNT}
RESULT=WARN
REASON=ollama_unavailable
EOF

  cat > "$PROOF_DIR/benchmark-summary.json" <<EOF
{
  "phase": "local-model-routing-phase5b-strict-benchmark",
  "result": "WARN",
  "mode": "real",
  "model": "${MODEL}",
  "benchmark_run": "no",
  "benchmark_verdict": "ollama_unavailable",
  "qwen25_recommendation": "none",
  "qwen25_decision": "do_not_wire_into_harness",
  "models_pulled": "no",
  "ollama_pull_attempted": "no",
  "live_routing_changed": "no"
}
EOF

  cat > "$PROOF_DIR/benchmark-summary.txt" <<'EOF'
RESULT=WARN
BENCHMARK_RUN=no
BENCHMARK_VERDICT=ollama_unavailable
QWEN25_RECOMMENDATION=none
QWEN25_DECISION=do_not_wire_into_harness
MODELS_PULLED=no
OLLAMA_PULL_ATTEMPTED=no
LIVE_ROUTING_CHANGED=no
EOF
}

write_real_mode_model_missing() {
  cat > "$PROOF_DIR/model-presence.txt" <<EOF
PHASE=local-model-routing-phase5b-strict-benchmark
MODE=real
MODEL=${MODEL}
OLLAMA_PRESENT=yes
QWEN25_MODEL_PRESENT=no
MODELS_PULLED=no
OLLAMA_PULL_ATTEMPTED=no
EOF

  cat > "$PROOF_DIR/benchmark-output.txt" <<'EOF'
PHASE=local-model-routing-phase5b-strict-benchmark
RESULT=WARN
BENCHMARK_RUN=no
BENCHMARK_VERDICT=model_missing
QWEN25_RECOMMENDATION=none
QWEN25_DECISION=do_not_wire_into_harness
MODELS_PULLED=no
OLLAMA_PULL_ATTEMPTED=no
LIVE_ROUTING_CHANGED=no
EOF

  cat > "$PROOF_DIR/benchmark-subset-summary.txt" <<EOF
STRICT_PROMPTS_RUN=no
STRICT_PROMPT_COUNT=${STRICT_PROMPT_COUNT}
RESULT=WARN
REASON=model_missing
EOF

  cat > "$PROOF_DIR/benchmark-summary.json" <<EOF
{
  "phase": "local-model-routing-phase5b-strict-benchmark",
  "result": "WARN",
  "mode": "real",
  "model": "${MODEL}",
  "benchmark_run": "no",
  "benchmark_verdict": "model_missing",
  "qwen25_recommendation": "none",
  "qwen25_decision": "do_not_wire_into_harness",
  "models_pulled": "no",
  "ollama_pull_attempted": "no",
  "live_routing_changed": "no"
}
EOF

  cat > "$PROOF_DIR/benchmark-summary.txt" <<'EOF'
RESULT=WARN
BENCHMARK_RUN=no
BENCHMARK_VERDICT=model_missing
QWEN25_RECOMMENDATION=none
QWEN25_DECISION=do_not_wire_into_harness
MODELS_PULLED=no
OLLAMA_PULL_ATTEMPTED=no
LIVE_ROUTING_CHANGED=no
EOF
}

write_real_mode_artifacts() {
  local list_out="$PROOF_DIR/ollama-list.txt"
  local subset_out="$PROOF_DIR/benchmark-subset-summary.txt"
  local bench_out="$PROOF_DIR/benchmark-output.txt"
  local pass_count=0
  local timeout_count=0
  local verdict="strict_prompt_fail"
  local result="WARN"
  local recommendation="none"

  cat > "$PROOF_DIR/ollama-command.txt" <<EOF
PHASE=local-model-routing-phase5b-strict-benchmark
MODE=real
OLLAMA_CALLED=yes
OLLAMA_CALL_SCOPE=list_and_run_${MODEL}
MODELS_PULLED=no
OLLAMA_PULL_ATTEMPTED=no
LIVE_ROUTING_CHANGED=no
COMMAND=timeout ${TIMEOUT_SECONDS}s ollama run ${MODEL}
EOF

  if ! command -v ollama > /dev/null 2>&1; then
    cat > "$list_out" <<'EOF'
OLLAMA_LIST_RUN=no
REASON=ollama_command_not_found
EOF
    write_real_mode_missing_ollama
    return 0
  fi

  if ! ollama list > "$list_out" 2>&1; then
    write_real_mode_missing_ollama
    return 0
  fi

  if ! grep -Eq '(^|[[:space:]])qwen2\.5:1\.5b([[:space:]]|$)' "$list_out"; then
    write_real_mode_model_missing
    return 0
  fi

  cat > "$PROOF_DIR/model-presence.txt" <<EOF
PHASE=local-model-routing-phase5b-strict-benchmark
MODE=real
MODEL=${MODEL}
OLLAMA_PRESENT=yes
QWEN25_MODEL_PRESENT=yes
MODELS_PULLED=no
OLLAMA_PULL_ATTEMPTED=no
EOF

  {
    run_prompt "route_hint_allow" "ALLOW" "Return exactly ALLOW. Task route_hint, risk LOW, touches none."
    run_prompt "route_hint_deny_code_generation" "DENY" "Return exactly DENY. Task code_generation, risk LOW, touches none."
    run_prompt "dirty_state_clean" "CLEAN" "Return exactly CLEAN. Git status has no changed files."
    run_prompt "dirty_state_dirty" "DIRTY" "Return exactly DIRTY. Git status has modified README.md."
    run_prompt "risk_label_secrets" "HIGH" "Return exactly HIGH. Task may read secrets."
    run_prompt "warn_fail_detect_pass" "PASS" "Return exactly PASS. RESULT=PASS and ASSERTIONS_FAILED=0."
    run_prompt "warn_fail_detect_warn" "WARN" "Return exactly WARN. RESULT=WARN and BENCHMARK_VERDICT=inconclusive."
    run_prompt "short_status_label_warn" "WARN" "Return exactly WARN. Status says deferred benchmark verdict."
  } > "$subset_out"

  pass_count="$(grep -c '=PASS ' "$subset_out" || true)"
  timeout_count="$(grep -c '=TIMEOUT_OR_ERROR ' "$subset_out" || true)"
  if [[ "$pass_count" -eq "$STRICT_PROMPT_COUNT" ]]; then
    verdict="strict_prompt_pass"
    result="PASS"
    recommendation="operator_review_required"
  elif [[ "$timeout_count" -gt 0 ]]; then
    verdict="inconclusive"
  fi

  cat > "$bench_out" <<EOF
PHASE=local-model-routing-phase5b-strict-benchmark
RESULT=${result}
BENCHMARK_RUN=yes
BENCHMARK_VERDICT=${verdict}
STRICT_PROMPT_COUNT=${STRICT_PROMPT_COUNT}
STRICT_PROMPT_PASS_COUNT=${pass_count}
STRICT_PROMPT_TIMEOUT_OR_ERROR_COUNT=${timeout_count}
QWEN25_RECOMMENDATION=${recommendation}
QWEN25_DECISION=do_not_wire_into_harness
MODELS_PULLED=no
OLLAMA_PULL_ATTEMPTED=no
LIVE_ROUTING_CHANGED=no
EOF

  cat > "$PROOF_DIR/benchmark-summary.json" <<EOF
{
  "phase": "local-model-routing-phase5b-strict-benchmark",
  "result": "${result}",
  "mode": "real",
  "model": "${MODEL}",
  "benchmark_run": "yes",
  "benchmark_verdict": "${verdict}",
  "strict_prompt_count": ${STRICT_PROMPT_COUNT},
  "strict_prompt_pass_count": ${pass_count},
  "strict_prompt_timeout_or_error_count": ${timeout_count},
  "qwen25_recommendation": "${recommendation}",
  "qwen25_decision": "do_not_wire_into_harness",
  "models_pulled": "no",
  "ollama_pull_attempted": "no",
  "live_routing_changed": "no"
}
EOF

  cat > "$PROOF_DIR/benchmark-summary.txt" <<EOF
RESULT=${result}
BENCHMARK_RUN=yes
BENCHMARK_VERDICT=${verdict}
QWEN25_RECOMMENDATION=${recommendation}
QWEN25_DECISION=do_not_wire_into_harness
STRICT_PROMPT_COUNT=${STRICT_PROMPT_COUNT}
STRICT_PROMPT_PASS_COUNT=${pass_count}
STRICT_PROMPT_TIMEOUT_OR_ERROR_COUNT=${timeout_count}
MODELS_PULLED=no
OLLAMA_PULL_ATTEMPTED=no
LIVE_ROUTING_CHANGED=no
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proof-dir)
      if [[ $# -lt 2 ]]; then
        printf 'ERROR: --proof-dir requires a value\n' >&2
        exit 2
      fi
      PROOF_DIR="$2"
      shift 2
      ;;
    --defer-model-run)
      DEFER_MODEL_RUN="yes"
      shift
      ;;
    --defer-reason)
      if [[ $# -lt 2 ]]; then
        printf 'ERROR: --defer-reason requires a value\n' >&2
        exit 2
      fi
      DEFER_REASON="$2"
      shift 2
      ;;
    --timeout-seconds)
      if [[ $# -lt 2 ]]; then
        printf 'ERROR: --timeout-seconds requires a value\n' >&2
        exit 2
      fi
      TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$PROOF_DIR" ]]; then
  printf 'ERROR: --proof-dir is required\n' >&2
  usage >&2
  exit 2
fi

case "$TIMEOUT_SECONDS" in
  ''|*[!0-9]*)
    printf 'ERROR: --timeout-seconds must be a positive integer\n' >&2
    exit 2
    ;;
  0)
    printf 'ERROR: --timeout-seconds must be greater than zero\n' >&2
    exit 2
    ;;
esac

refuse_unsafe_proof_dir
mkdir -p -m 0700 "$PROOF_DIR"

if [[ "$DEFER_MODEL_RUN" == "yes" ]]; then
  if [[ -z "$DEFER_REASON" ]]; then
    DEFER_REASON="deferred by operator"
  fi
  write_deferred_artifacts
else
  write_real_mode_artifacts
fi

write_artifact_presence
cat "$PROOF_DIR/benchmark-summary.txt"
