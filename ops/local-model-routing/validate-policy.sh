#!/usr/bin/env bash
set -euo pipefail

POLICY="${1:-config/local-model-routing.policy.json}"

python3 - "$POLICY" <<'PY'
import json, sys
from pathlib import Path

p = Path(sys.argv[1])
checks = []

def chk(name, ok):
    checks.append((name, bool(ok)))

def has_all(values, required):
    values = values or []
    return all(x in values for x in required)

if not p.exists():
    print("PHASE=local-model-routing-policy-validator")
    print("RESULT=FAIL")
    print(f"POLICY_PATH={p}")
    print("POLICY_VALID=no")
    print("ASSERTIONS_TOTAL=1")
    print("ASSERTIONS_FAILED=1")
    raise SystemExit(1)

data = json.loads(p.read_text())
default = data.get("defaultBehavior", {})
machines = data.get("machines", {})
nuc1 = machines.get("nuc1", {})
nuc2 = machines.get("nuc2", {})
ollama = nuc1.get("ollama", {})
models = ollama.get("allowedModels", {})
q25 = models.get("qwen2.5:1.5b", {})
q3 = models.get("qwen3:4b", {})
hermes = nuc1.get("hermes", {})
nuc2inf = nuc2.get("localInference", {})
proof = data.get("proofRequirements", {})
routing_raw = data.get("routingRules", [])
rules_dict = routing_raw if isinstance(routing_raw, dict) else {}
rules = list(routing_raw.values()) if isinstance(routing_raw, dict) else routing_raw

protected = {"secrets","caddy","dns","systemd","cron","tmux","discord_webhook","auth","production_routing"}

chk("status_policy_only_not_live", data.get("status") == "policy_only_not_live")
chk("acceptedByOperator_false", data.get("acceptedByOperator") is False)
chk("localModelsAreAdvisoryOnly_true", default.get("localModelsAreAdvisoryOnly") is True)
chk("harnessQaRemainsSourceOfTruth_true", default.get("harnessQaRemainsSourceOfTruth") is True)
chk("noProductionEditsByLocalModels_true", default.get("noProductionEditsByLocalModels") is True)
chk("noFinalQaByLocalModels_true", default.get("noFinalQaByLocalModels") is True)
chk("noSecretsByLocalModels_true", default.get("noSecretsByLocalModels") is True)
chk("noDiscordWebhookAccessByLocalModels_true", default.get("noDiscordWebhookAccessByLocalModels") is True)

chk("nuc1_role_primary_production", "primary_production" in nuc1.get("role", []))
chk("nuc1_role_local_model_helper", "local_model_helper" in nuc1.get("role", []))
chk("ollama_endpoint_local", ollama.get("endpoint") == "http://127.0.0.1:11434")

chk("qwen25_enabled_true", q25.get("enabled") is True)
chk("qwen25_max_tokens_8", q25.get("maxOutputTokensHotPath") == 8)
chk("qwen25_max_wall_10", q25.get("maxWallSecondsHotPath") == 10)
chk("qwen25_allowed_tasks", has_all((q25.get("allowedTasks") or q25.get("allowedTinyHelperTasks")), ["route_hint","risk_label","warn_fail_detect","dirty_state_label","short_status_label"]))
chk("qwen25_denied_tasks", has_all(q25.get("deniedTasks"), ["code_generation","production_editing","final_qa","secret_handling","discord_notification","caddy_dns_systemd_cron_changes","database_migration","large_summarization"]))

chk("qwen3_enabled_false", q3.get("enabled") is False)
chk("qwen3_do_not_use_hot_path", q3.get("decision") == "do_not_use_hot_path")
chk("qwen3_denied_tasks", has_all(q3.get("deniedTasks"), ["hot_path_routing","code_generation","production_editing","final_qa","secret_handling","large_summarization"]))

chk("nuc2_role_report_rendering_worker", "report_rendering_worker" in nuc2.get("role", []))
chk("nuc2_role_relay_only_worker", "relay_only_worker" in nuc2.get("role", []))
chk("nuc2_local_inference_false", nuc2inf.get("enabled") is False)
chk("nuc2_do_not_use_hot_path", nuc2inf.get("decision") == "do_not_use_hot_path")
chk("nuc2_future_model", nuc2inf.get("optionalFutureBackgroundModel") == "qwen2.5:0.5b")
chk("nuc2_denied_tasks", has_all(nuc2inf.get("deniedTasks"), ["code_generation","hot_path_routing","large_summarization","production_editing","final_qa","secret_handling","discord_webhook_storage"]))

chk("hermes_enabled_false", hermes.get("enabled") is False)
chk("hermes_unknown_backend", hermes.get("status") == "unknown_model_backend")
chk("port8080_caddy_not_hermes", hermes.get("port8080Identity") == "caddy_not_hermes")

chk("high_risk_local_denied", (rules_dict.get("highRiskTasks", {}).get("localModelAllowed") is False) or any(r.get("match", {}).get("taskRisk") == "HIGH" and r.get("localModelAllowed") is False for r in rules))
chk("protected_surfaces_local_denied", (rules_dict.get("protectedSurfaces", {}).get("localModelAllowed") is False and protected.issubset(set(rules_dict.get("protectedSurfaces", {}).get("surfaces", [])))) or any(protected.issubset(set(r.get("match", {}).get("touches", []))) and r.get("localModelAllowed") is False for r in rules))

chk("proof_decision_logged", proof.get("localModelDecisionMustBeLogged") is True)
chk("proof_output_advisory", proof.get("localModelOutputIsAdvisory") is True)
chk("proof_manual_qa_required", proof.get("manualQaRequiredBeforeLiveRouting") is True)
chk("proof_closeout_required", proof.get("closeoutRequiredBeforeAcceptedState") is True)

failed = [name for name, ok in checks if not ok]

print("PHASE=local-model-routing-policy-validator")
print("RESULT=" + ("PASS" if not failed else "FAIL"))
print(f"POLICY_PATH={p}")
print("POLICY_VALID=" + ("yes" if not failed else "no"))
print("LIVE_ROUTING_ENABLED=no")
print("OLLAMA_CALLED=no")
print("MODELS_PULLED=no")
print("LOCAL_MODELS_ADVISORY_ONLY=" + ("yes" if default.get("localModelsAreAdvisoryOnly") is True else "no"))
print("HARNESS_QA_SOURCE_OF_TRUTH=&#".replace("&#", "yes" if default.get("harnessQaRemainsSourceOfTruth") is True else "no"))
print("QWEN25_15B_TINY_HELPER_ONLY=" + ("yes" if q25.get("enabled") is True and q25.get("maxOutputTokensHotPath") == 8 and q25.get("maxWallSecondsHotPath") == 10 else "no"))
print("QWEN3_4B_HOT_PATH_DISABLED=" + ("yes" if q3.get("enabled") is False and q3.get("decision") == "do_not_use_hot_path" else "no"))
print("NUC2_HOT_PATH_DISABLED=" + ("yes" if nuc2inf.get("enabled") is False and nuc2inf.get("decision") == "do_not_use_hot_path" else "no"))
print("HERMES_DISABLED=" + ("yes" if hermes.get("enabled") is False else "no"))
print(f"ASSERTIONS_TOTAL={len(checks)}")
print(f"ASSERTIONS_FAILED={len(failed)}")
if failed:
    print("FAILED_ASSERTIONS=" + ",".join(failed))
    raise SystemExit(1)
PY
