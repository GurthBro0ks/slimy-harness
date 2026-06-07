#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MACHINE_NAME="${HARNESS_MACHINE_NAME:-$(hostname)}"
DEFAULT_USER="${USER:-unknown}"
KEYWORD_PATTERN='harness|kb|research|gh-tracker|habitat|watchdog|report|notify|slimy'

log() { echo "[schedule-inventory] $*"; }
warn() { echo "[schedule-inventory] WARN: $*"; }

usage() {
  cat <<'USG'
discover-schedules.sh — read-only schedule inventory

Usage:
  ops/harness-ops schedule inventory

Behavior:
  - inventories cron sources and systemd timers read-only
  - redacts secret-looking values
  - may attempt optional read-only NUC2 inspection via ssh host `nuc2`
  - does NOT run jobs, edit cron, or change timer/service state
USG
}

redact_text() {
  local text="$1"
  local hook_host='dis''cord'
  local hook_app='app'
  local hook_path='/api/webhooks/'
  printf '%s' "$text" | sed -E \
    -e "s#https://${hook_host}(${hook_app})?\\.com${hook_path}[A-Za-z0-9/_-]+#[REDACTED_DISCORD_WEBHOOK]#g" \
    -e 's#(https?://)[^ /:@]+:[^ /@]+@#\1[REDACTED]@#g' \
    -e 's/\b([Bb]earer)[[:space:]]+[A-Za-z0-9._~+\/=:-]+/\1 [REDACTED]/g' \
    -e 's/\b([A-Za-z_][A-Za-z0-9_]*(SECRET|TOKEN|KEY|PASSWORD|WEBHOOK|COOKIE|SESSION)[A-Za-z0-9_]*)=([^[:space:]]+)/\1=[REDACTED]/g' \
    -e 's/([?&](token|secret|key|password|session|cookie)=)[^&[:space:]]+/\1[REDACTED]/Ig'
}

compact_text() {
  local text="$1"
  text="$(printf '%s' "$text" | tr '\t' ' ' | tr -s ' ')"
  text="${text# }"
  text="${text% }"
  if [[ ${#text} -gt 220 ]]; then
    text="${text:0:217}..."
  fi
  printf '%s' "$text"
}

guess_project() {
  local haystack="$1"
  shopt -s nocasematch
  local project="unknown"
  if [[ "$haystack" =~ gh-tracker|habitat ]]; then
    project="gh-tracker"
  elif [[ "$haystack" =~ kb|wiki-manager|kb-maintenance|obsidian|calendar-sync ]]; then
    project="kb"
  elif [[ "$haystack" =~ research ]]; then
    project="research-farm"
  elif [[ "$haystack" =~ harness|notify|report|sequencer ]]; then
    project="slimy-harness"
  elif [[ "$haystack" =~ slimy-chat ]]; then
    project="slimy-chat"
  fi
  shopt -u nocasematch
  printf '%s' "$project"
}

guess_risk() {
  local haystack="$1"
  shopt -s nocasematch
  local risk="unknown"
  if [[ "$haystack" =~ discord|webhook|notify|restart|reload|deploy|publish|caddy|auto-sequence|sync-session-reports ]]; then
    risk="high"
  elif [[ "$haystack" =~ maintenance|compile|sync|report|backup|lint|calendar|daily|obsidian ]]; then
    risk="medium"
  elif [[ "$haystack" =~ status|inventory|check|validate|watchdog ]]; then
    risk="low"
  fi
  shopt -u nocasematch
  printf '%s' "$risk"
}

print_entry() {
  local machine="$1"
  local schedule_type="$2"
  local owner="$3"
  local source="$4"
  local job_name="$5"
  local command_summary="$6"
  local next_run="$7"
  local last_run="$8"
  local state="$9"
  local notes="${10}"

  command_summary="$(compact_text "$(redact_text "$command_summary")")"
  notes="$(compact_text "$(redact_text "$notes")")"
  local project_guess
  local risk
  project_guess="$(guess_project "$job_name $source $command_summary $notes")"
  risk="$(guess_risk "$job_name $source $command_summary $notes")"

  echo "---"
  echo "machine: $machine"
  echo "schedule_type: $schedule_type"
  echo "owner: $owner"
  echo "source: $source"
  echo "unit_or_job: $job_name"
  echo "command_summary: $command_summary"
  echo "next_run: ${next_run:-unknown}"
  echo "last_run: ${last_run:-unknown}"
  echo "state: ${state:-unknown}"
  echo "project_guess: $project_guess"
  echo "risk: $risk"
  echo "notes: ${notes:-none}"
}

print_skip() {
  print_entry "$MACHINE_NAME" "skipped" "$DEFAULT_USER" "$1" "$2" "read-only inspection skipped" "n/a" "n/a" "skipped" "$3"
}

emit_user_crontab() {
  local machine="$1"
  local owner="$2"
  local source="$3"
  local content="$4"
  while IFS= read -r line; do
    [[ -z "${line// }" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      print_entry "$machine" "user_crontab_env" "$owner" "$source" "env_assignment" "$line" "n/a" "n/a" "configured" "redacted env assignment in crontab"
      continue
    fi
    local schedule=""
    local command_summary=""
    if [[ "$line" =~ ^@ ]]; then
      schedule="${line%% *}"
      command_summary="${line#* }"
    else
      schedule="$(printf '%s\n' "$line" | awk '{print $1" "$2" "$3" "$4" "$5}')"
      command_summary="$(printf '%s\n' "$line" | awk '{$1=""; $2=""; $3=""; $4=""; $5=""; sub(/^ +/, ""); print}')"
    fi
    print_entry "$machine" "user_crontab" "$owner" "$source" "$schedule" "$command_summary" "n/a" "n/a" "configured" "user crontab entry"
  done <<< "$content"
}

emit_system_cron_file() {
  local machine="$1"
  local source="$2"
  local file_path="$3"
  while IFS= read -r line; do
    [[ -z "${line// }" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      print_entry "$machine" "system_cron_env" "root" "$source" "env_assignment" "$line" "n/a" "n/a" "configured" "$file_path"
      continue
    fi
    local owner="root"
    local schedule=""
    local command_summary=""
    if [[ "$line" =~ ^@ ]]; then
      schedule="${line%% *}"
      owner="$(printf '%s\n' "$line" | awk '{print $2}')"
      command_summary="$(printf '%s\n' "$line" | awk '{$1=""; $2=""; sub(/^ +/, ""); print}')"
    else
      schedule="$(printf '%s\n' "$line" | awk '{print $1" "$2" "$3" "$4" "$5}')"
      owner="$(printf '%s\n' "$line" | awk '{print $6}')"
      command_summary="$(printf '%s\n' "$line" | awk '{$1=""; $2=""; $3=""; $4=""; $5=""; $6=""; sub(/^ +/, ""); print}')"
    fi
    print_entry "$machine" "system_cron" "$owner" "$source" "$schedule" "$command_summary" "n/a" "n/a" "configured" "$file_path"
  done < "$file_path"
}

emit_periodic_dir() {
  local machine="$1"
  local source="$2"
  local dir_path="$3"
  if [[ ! -d "$dir_path" ]]; then
    print_skip "$source" "$dir_path" "directory missing"
    return
  fi
  local found=0
  local path
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    found=1
    local owner
    owner="$(stat -c '%U' "$path" 2>/dev/null || printf 'unknown')"
    print_entry "$machine" "periodic_dir" "$owner" "$source" "$(basename "$path")" "$path" "n/a" "n/a" "present" "$dir_path"
  done < <(find "$dir_path" -mindepth 1 -maxdepth 1 -type f 2>/dev/null | sort)
  if [[ "$found" -eq 0 ]]; then
    print_entry "$machine" "periodic_dir" "root" "$source" "(empty)" "$dir_path" "n/a" "n/a" "present" "directory has no files"
  fi
}

emit_timer_inventory() {
  local machine="$1"
  local mode="$2"
  local owner="$3"
  local prefix=()
  if [[ "$mode" == "user" ]]; then
    prefix=(systemctl --user)
  else
    prefix=(systemctl)
  fi

  local timers_raw
  if ! timers_raw="$(${prefix[@]} list-timers --all --no-legend --no-pager 2>/dev/null | awk '{print $(NF-1)}')"; then
    print_skip "${mode}_systemd_timers" "systemctl ${mode}" "command unavailable or access denied"
    return
  fi

  if [[ -z "${timers_raw// }" ]]; then
    print_entry "$machine" "${mode}_systemd_timer" "$owner" "${mode}_systemd_timers" "(none)" "no timers listed" "n/a" "n/a" "none" "systemctl reported no timers"
    return
  fi

  local unit
  while IFS= read -r unit; do
    [[ -z "$unit" ]] && continue
    local props=""
    props="$(${prefix[@]} show "$unit" --no-pager --property=Id,Unit,Description,NextElapseUSecRealtime,LastTriggerUSec,ActiveState,SubState 2>/dev/null || true)"
    local activates next_run last_run active_state sub_state description
    activates="$(printf '%s\n' "$props" | sed -n 's/^Unit=//p')"
    next_run="$(printf '%s\n' "$props" | sed -n 's/^NextElapseUSecRealtime=//p')"
    last_run="$(printf '%s\n' "$props" | sed -n 's/^LastTriggerUSec=//p')"
    active_state="$(printf '%s\n' "$props" | sed -n 's/^ActiveState=//p')"
    sub_state="$(printf '%s\n' "$props" | sed -n 's/^SubState=//p')"
    description="$(printf '%s\n' "$props" | sed -n 's/^Description=//p')"
    print_entry "$machine" "${mode}_systemd_timer" "$owner" "${mode}_systemd_timers" "$unit" "activates=${activates:-unknown}; description=${description:-none}" "${next_run:-n/a}" "${last_run:-n/a}" "${active_state:-unknown}/${sub_state:-unknown}" "timer unit"
  done <<< "$timers_raw"
}

emit_keyword_unit_matches() {
  local machine="$1"
  local mode="$2"
  local owner="$3"
  local prefix=()
  if [[ "$mode" == "user" ]]; then
    prefix=(systemctl --user)
  else
    prefix=(systemctl)
  fi

  local matches
  matches="$(${prefix[@]} list-unit-files --type=service --type=timer --no-legend --no-pager 2>/dev/null | grep -Ei "$KEYWORD_PATTERN" || true)"
  if [[ -z "${matches// }" ]]; then
    print_entry "$machine" "${mode}_unit_match" "$owner" "${mode}_unit_files" "(none)" "no matching service/timer units" "n/a" "n/a" "none" "keyword filter=$KEYWORD_PATTERN"
    return
  fi
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local unit_name state
    unit_name="$(printf '%s\n' "$line" | awk '{print $1}')"
    state="$(printf '%s\n' "$line" | awk '{print $2}')"
    print_entry "$machine" "${mode}_unit_match" "$owner" "${mode}_unit_files" "$unit_name" "$line" "n/a" "n/a" "$state" "keyword unit/service match"
  done <<< "$matches"
}

emit_remote_optional() {
  if ! command -v ssh >/dev/null 2>&1; then
    print_skip "remote_nuc2_optional" "nuc2" "ssh client unavailable"
    return
  fi
  if ! ssh -o BatchMode=yes -o ConnectTimeout=5 nuc2 "hostname" >/dev/null 2>&1; then
    print_skip "remote_nuc2_optional" "nuc2" "ssh host unavailable or not configured for non-interactive read-only access"
    return
  fi

  local remote_user_cron
  remote_user_cron="$(ssh -o BatchMode=yes -o ConnectTimeout=5 nuc2 "crontab -l 2>/dev/null || true" 2>/dev/null || true)"
  if [[ -n "${remote_user_cron// }" ]]; then
    emit_user_crontab "nuc2" "slimy" "nuc2:user_crontab" "$remote_user_cron"
  else
    print_entry "nuc2" "user_crontab" "slimy" "nuc2:user_crontab" "(none)" "no user crontab entries returned" "n/a" "n/a" "none" "optional remote inspection"
  fi

  local remote_timers
  remote_timers="$(ssh -o BatchMode=yes -o ConnectTimeout=5 nuc2 "systemctl --user list-timers --all --no-legend --no-pager 2>/dev/null | awk '{print \$(NF-1)}' || true" 2>/dev/null || true)"
  if [[ -n "${remote_timers// }" ]]; then
    while IFS= read -r unit; do
      [[ -z "$unit" ]] && continue
      print_entry "nuc2" "user_systemd_timer" "slimy" "nuc2:user_systemd_timers" "$unit" "optional remote timer unit" "unknown" "unknown" "listed" "remote details intentionally shallow to stay read-only"
    done <<< "$remote_timers"
  else
    print_entry "nuc2" "user_systemd_timer" "slimy" "nuc2:user_systemd_timers" "(none or unavailable)" "no remote user timers listed" "n/a" "n/a" "unknown" "optional remote inspection"
  fi
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "[schedule-inventory] ERROR: unknown arg: $1" >&2
      exit 2
      ;;
  esac
fi

echo "# Harness Ops Schedule Inventory"
echo "generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "machine: $MACHINE_NAME"
echo "mode: read-only"
echo "redaction: enabled"
echo "notes: no jobs were run; no cron or timer state was changed"

if command -v crontab >/dev/null 2>&1; then
  user_cron="$(crontab -l 2>/dev/null || true)"
  if [[ -n "${user_cron// }" ]]; then
    emit_user_crontab "$MACHINE_NAME" "$DEFAULT_USER" "user_crontab" "$user_cron"
  else
    print_entry "$MACHINE_NAME" "user_crontab" "$DEFAULT_USER" "user_crontab" "(none)" "no user crontab entries" "n/a" "n/a" "none" "crontab -l returned no entries"
  fi
else
  print_skip "user_crontab" "crontab -l" "crontab command unavailable"
fi

print_skip "root_crontab" "root crontab" "requires root/sudo; skipped in read-only unprivileged pass"

if [[ -r /etc/crontab ]]; then
  emit_system_cron_file "$MACHINE_NAME" "system_crontab" "/etc/crontab"
else
  print_skip "system_crontab" "/etc/crontab" "file unreadable or missing"
fi

if [[ -d /etc/cron.d ]]; then
  found_crond=0
  while IFS= read -r cron_file; do
    [[ -z "$cron_file" ]] && continue
    found_crond=1
    emit_system_cron_file "$MACHINE_NAME" "cron_d" "$cron_file"
  done < <(find /etc/cron.d -mindepth 1 -maxdepth 1 -type f 2>/dev/null | sort)
  if [[ "$found_crond" -eq 0 ]]; then
    print_entry "$MACHINE_NAME" "system_cron" "root" "cron_d" "(empty)" "/etc/cron.d" "n/a" "n/a" "present" "directory has no files"
  fi
else
  print_skip "cron_d" "/etc/cron.d" "directory missing"
fi

emit_periodic_dir "$MACHINE_NAME" "cron_hourly" "/etc/cron.hourly"
emit_periodic_dir "$MACHINE_NAME" "cron_daily" "/etc/cron.daily"
emit_periodic_dir "$MACHINE_NAME" "cron_weekly" "/etc/cron.weekly"
emit_periodic_dir "$MACHINE_NAME" "cron_monthly" "/etc/cron.monthly"

emit_timer_inventory "$MACHINE_NAME" "system" "root"
emit_timer_inventory "$MACHINE_NAME" "user" "$DEFAULT_USER"
emit_keyword_unit_matches "$MACHINE_NAME" "system" "root"
emit_keyword_unit_matches "$MACHINE_NAME" "user" "$DEFAULT_USER"
emit_remote_optional
