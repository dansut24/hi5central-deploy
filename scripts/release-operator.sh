#!/bin/sh
set -eu

API_URL=${RELEASE_CONTROL_API_URL:?RELEASE_CONTROL_API_URL is required}
TOKEN_FILE=${RELEASE_OPERATOR_TOKEN_FILE:-/config/operator.token}
LIVE_PROMOTION_ENABLED=${LIVE_PROMOTION_ENABLED:-0}
POLL_SECONDS=${RELEASE_OPERATOR_POLL_SECONDS:-10}
COMPOSE_FILE=/operator/compose.yml
EDGE_FILE=/operator/compose.release-edge.yml

[ -s "$TOKEN_FILE" ] || { echo "Missing release operator token file: $TOKEN_FILE" >&2; exit 1; }
TOKEN=$(cat "$TOKEN_FILE")
[ "${#TOKEN}" -ge 32 ] || { echo "Release operator token is too short." >&2; exit 1; }

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

api_post() {
  path=$1
  body=$2
  curl -fsS     -H "Authorization: Bearer $TOKEN"     -H 'Content-Type: application/json'     -X POST     --data "$body"     "$API_URL$path"
}

env_value() {
  file=$1
  key=$2
  awk -F= -v key="$key" '$1==key { print substr($0,index($0,"=")+1); exit }' "$file"
}

guard_environment() {
  expected=$1
  file="/config/$expected.env"
  [ -s "$file" ] || { echo "Missing $file" >&2; return 1; }
  runtime=$(env_value "$file" RUNTIME_ENVIRONMENT)
  project=$(env_value "$file" COMPOSE_PROJECT_NAME)
  case "$expected" in
    test)
      [ "$runtime" = test ] && [ "$project" = hi5central-test ] || return 1
      ;;
    uat)
      [ "$runtime" = uat ] && [ "$project" = hi5central-uat ] || return 1
      ;;
    live)
      [ "$runtime" = live ] && [ "$project" = hi5central-prod ] || return 1
      ;;
    *) return 1 ;;
  esac
  printf '%s' "$file"
}

compose_env() {
  environment=$1
  shift
  file=$(guard_environment "$environment")
  docker compose -f "$COMPOSE_FILE" -f "$EDGE_FILE" --env-file "$file" "$@"
}

wait_service() {
  environment=$1
  service=$2
  attempts=0
  while :; do
    cid=$(compose_env "$environment" ps -q "$service" 2>/dev/null || true)
    [ -n "$cid" ] || { sleep 2; attempts=$((attempts+1)); [ "$attempts" -lt 90 ] || return 1; continue; }
    status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo missing)
    [ "$status" = healthy ] && return 0
    case "$status" in exited|dead|unhealthy) return 1 ;; esac
    attempts=$((attempts+1))
    [ "$attempts" -lt 90 ] || return 1
    sleep 2
  done
}

wait_stack() {
  environment=$1
  for service in postgres redis control-server itsm-web rmm-web admin-web; do
    wait_service "$environment" "$service" || {
      echo "$environment service $service failed health gate." >&2
      return 1
    }
  done
}

image_digest() {
  environment=$1
  service=$2
  cid=$(compose_env "$environment" ps -q "$service")
  [ -n "$cid" ] || return 1
  image_id=$(docker inspect -f '{{.Image}}' "$cid")
  [ -n "$image_id" ] || return 1
  digest=$(docker image inspect -f '{{range .RepoDigests}}{{println .}}{{end}}' "$image_id" | head -1)
  case "$digest" in
    *@sha256:*) printf '%s' "$digest" ;;
    *) echo "No immutable repository digest found for $environment/$service ($image_id)." >&2; return 1 ;;
  esac
}

capture_manifest() {
  environment=$1
  control=$(image_digest "$environment" control-server)
  itsm=$(image_digest "$environment" itsm-web)
  rmm=$(image_digest "$environment" rmm-web)
  admin=$(image_digest "$environment" admin-web)
  jq -cn     --arg controlServer "$control"     --arg itsm "$itsm"     --arg rmm "$rmm"     --arg admin "$admin"     '{controlServer:$controlServer,itsm:$itsm,rmm:$rmm,admin:$admin}'
}

set_env_value() {
  file=$1
  key=$2
  value=$3
  tmp="$file.tmp.$$"
  awk -v key="$key" -v value="$value" '
    BEGIN { found=0 }
    index($0,key "=")==1 { print key "=" value; found=1; next }
    { print }
    END { if (!found) print key "=" value }
  ' "$file" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$file"
}

pin_manifest() {
  environment=$1
  manifest=$2
  file=$(guard_environment "$environment")
  set_env_value "$file" CONTROL_SERVER_IMAGE "$(printf '%s' "$manifest" | jq -r .controlServer)"
  set_env_value "$file" ITSM_IMAGE "$(printf '%s' "$manifest" | jq -r .itsm)"
  set_env_value "$file" RMM_IMAGE "$(printf '%s' "$manifest" | jq -r .rmm)"
  set_env_value "$file" ADMIN_IMAGE "$(printf '%s' "$manifest" | jq -r .admin)"
}

complete_action() {
  id=$1
  status=$2
  release_ref=$3
  error_message=$4
  manifest=$5
  body=$(jq -cn     --arg status "$status"     --arg releaseRef "$release_ref"     --arg errorMessage "$error_message"     --argjson manifest "$manifest"     '{status:$status,releaseRef:$releaseRef,errorMessage:$errorMessage,details:{manifest:$manifest}}')
  api_post "/api/platform-operator/v1/actions/$id/complete" "$body" >/dev/null
}

reset_test() {
  log "Resetting disposable Test environment."
  guard_environment test >/dev/null
  compose_env test down -v --remove-orphans
  compose_env test pull
  compose_env test up -d --remove-orphans
  wait_stack test
  manifest=$(capture_manifest test)
  ref="test-reset-$(date -u +%Y%m%dT%H%M%SZ)"
  printf '%s\n%s\n' "$ref" "$manifest"
}

promote_environment() {
  target=$1
  case "$target" in
    uat) source=test ;;
    live)
      source=uat
      [ "$LIVE_PROMOTION_ENABLED" = 1 ] || {
        echo "Live promotion is disabled until managed Live cutover is enabled." >&2
        return 2
      }
      ;;
    *) return 1 ;;
  esac

  guard_environment "$source" >/dev/null
  guard_environment "$target" >/dev/null
  wait_stack "$source"
  manifest=$(capture_manifest "$source")
  pin_manifest "$target" "$manifest"

  log "Deploying $target from exact $source image digests."
  compose_env "$target" pull
  compose_env "$target" up -d --remove-orphans
  wait_stack "$target"
  printf '%s' "$manifest"
}

process_action() {
  response=$1
  id=$(printf '%s' "$response" | jq -r '.action.id // empty')
  [ -n "$id" ] || return 0
  environment=$(printf '%s' "$response" | jq -r '.action.environment')
  action=$(printf '%s' "$response" | jq -r '.action.action')
  requested_ref=$(printf '%s' "$response" | jq -r '.action.payload.releaseRef // empty')
  log "Claimed action $id: $action -> $environment"

  status=succeeded
  error_message=
  release_ref=$requested_ref
  manifest='{}'

  set +e
  case "$action:$environment" in
    reset:test)
      output=$(reset_test 2>&1)
      rc=$?
      if [ "$rc" -eq 0 ]; then
        release_ref=$(printf '%s\n' "$output" | tail -2 | head -1)
        manifest=$(printf '%s\n' "$output" | tail -1)
      else
        error_message=$output
      fi
      ;;
    promote:uat|promote:live)
      output=$(promote_environment "$environment" 2>&1)
      rc=$?
      if [ "$rc" -eq 0 ]; then
        manifest=$(printf '%s\n' "$output" | tail -1)
      else
        error_message=$output
      fi
      ;;
    *)
      rc=1
      error_message="Unsupported release action: $action -> $environment"
      ;;
  esac
  set -e

  if [ "$rc" -ne 0 ]; then
    status=failed
    manifest='{}'
    error_message=$(printf '%s' "$error_message" | tail -c 3500)
    log "Action $id failed: $error_message"
  else
    log "Action $id succeeded."
  fi
  complete_action "$id" "$status" "$release_ref" "$error_message" "$manifest"
}

run_once() {
  response=$(api_post '/api/platform-operator/v1/actions/claim' '{}')
  process_action "$response"
}

if [ "${1:-}" = "--once" ]; then
  run_once
  exit 0
fi

log "Hi5Central release operator started for $API_URL."
while :; do
  if ! run_once; then
    log "Release operator iteration failed; retrying."
  fi
  sleep "$POLL_SECONDS"
done
