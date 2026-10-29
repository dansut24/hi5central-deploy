#!/usr/bin/env bash
# Read-only verification of the 2026-10-29 RMM production baseline.
# No container restart and no database access.
set -Eeuo pipefail

want_web='sha256:b01463acf22bc3952e357eaf43fdec275016ace019bd219fc1d84694a2b49d22'
# Approved UI-only overlay from Platform PR #160; viewer files remain pinned.
allowed_inventory_ui_web='sha256:defad69f0c6dc7fe22957298640123575febbe0a74541bb50aac710abdee3ee9'
# New 1.0.134 test installer added to the approved inventory UI image only.
allowed_deep_inventory_agent_web='sha256:81f731e71a0a84e28d5d5ad26368a47ed87731ff49f31f846babfa11baf3f2be'
want_api='sha256:9542d8537f8a003c2230aa17ff06b56f6ffed605740bb9952ea0b6ba54210f45'
want_viewer_html='a233420273a482f7c4d45d8e7f3e34d489ba794e0f19af587e3a9b1fe9ff2281'
want_viewer_js='1e61ef9e80a00dc2d9428269c76a01462cbc575826bf026ff39ee739387258d6'
want_agent='87baf2cd6d97826392b0dc757e1a5b19c3fd7aabe657dfa30dc5661d0513dc76'
installer="${H5C_AGENT_INSTALLER:-/opt/hi5central/runtime/rmm/shared/privileged-input-pr78-20261029/Hi5CentralAgentSetup-1.0.130.exe}"

check() {
  local name="$1" actual="$2" expected="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf 'DRIFT %-20s expected=%s actual=%s\n' "$name" "$expected" "$actual" >&2
    return 1
  fi
  printf 'OK    %-20s %s\n' "$name" "$actual"
}
failed=0
web_id="$(docker inspect hi5central-rmm-web-1 --format '{{.Image}}')"
api_id="$(docker inspect hi5central-rmm-api-1 --format '{{.Image}}')"
if [[ "$web_id" == "$want_web" ]]; then
  echo "OK    web-image            $web_id (original protected release)"
elif [[ "$web_id" == "$allowed_inventory_ui_web" ]]; then
  echo "OK    web-image            $web_id (approved inventory UI overlay)"
elif [[ "$web_id" == "$allowed_deep_inventory_agent_web" ]]; then
  echo "OK    web-image            $web_id (approved Agent 1.0.134 test download on locked Viewer)"
else
  printf 'DRIFT web-image            %s not on approved list\n' "$web_id" >&2
  failed=1
fi
check api-image "$api_id" "$want_api" || failed=1
while read -r hash path; do
  case "$path" in
    /srv/rmm-viewer/index.html) check viewer-html "$hash" "$want_viewer_html" || failed=1 ;;
    /srv/rmm-viewer/renderer.js) check viewer-renderer "$hash" "$want_viewer_js" || failed=1 ;;
  esac
done < <(docker exec hi5central-rmm-web-1 sha256sum /srv/rmm-viewer/index.html /srv/rmm-viewer/renderer.js)
if [[ -f "$installer" ]]; then
  check agent-installer "$(sha256sum "$installer" | cut -d' ' -f1)" "$want_agent" || failed=1
else
  printf 'MISSING Agent installer %s\n' "$installer" >&2
  failed=1
fi
# Preserve the stable Agent 1.0.130 installer above. Also verify the separately
# published, not-yet-installed 1.0.134 test installer whenever it is available.
new_installer='/opt/hi5central/runtime/rmm/shared/deep-inventory-pr79-20261029/Hi5CentralAgentSetup-1.0.134.exe'
if [[ "$web_id" == "$allowed_deep_inventory_agent_web" ]]; then
  if [[ -f "$new_installer" ]]; then
    check test-installer-134 "$(sha256sum "$new_installer" | cut -d' ' -f1)" '4b4c0edaa78ecce85427dc1b8642e4f3975cf6295f8a45c1ae7cbfa6d3491d08' || failed=1
  else
    echo "MISSING published 1.0.134 test installer" >&2
    failed=1
  fi
fi
if [[ "$failed" -ne 0 ]]; then
  echo 'RMM baseline verification FAILED. Do not replace the known-good runtime.' >&2
  exit 1
fi
echo 'RMM baseline verified. No services were changed.'
