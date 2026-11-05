#!/usr/bin/env bash
#
# ct/crowdsec.sh - CrowdSec Security Engine, as the central Local API for
# your network.
#
# Run on the Proxmox VE host as root:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/crowdsec.sh)"
#
# From a local checkout (loads the engine from disk instead of GitHub):
#   RECIPES_SRC=/path/to/proxmox-recipes bash ct/crowdsec.sh
#
# From another branch or tag on GitHub (default main):
#   RECIPES_REF=<branch> bash ct/crowdsec.sh
#
# Option (preset it to skip the question):
#   CROWDSEC_SHARING=yes|no   share attack signals with CrowdSec's Central
#                             API and get its community blocklist (default no)

set -Eeuo pipefail

# shellcheck disable=SC2034  # read by misc/build.func
{
  APP_NAME="CrowdSec"
  APP_SLUG="crowdsec"
  APP_DEBIAN_RELEASE=12
  APP_DEFAULT_HOSTNAME="crowdsec"
  APP_DEFAULT_CORES=1
  APP_DEFAULT_RAM_MB=1024
  APP_DEFAULT_DISK_GB=4
  APP_INSTALL_SCRIPT="install/crowdsec.sh"
  APP_ENV_VARS=(CROWDSEC_SHARING)
}

app_ask_options() {
  ui_yesno CROWDSEC_SHARING "Share attack signals with CrowdSec?

Yes: CrowdSec registers this server with its Central API. When it detects an attack, it sends the attacker's IP, the scenario that caught it and a timestamp to CrowdSec. In return you get the community blocklist of IPs that attack other users.

No (default): nothing is sent to CrowdSec. You only block what your own agents detect, plus any lists you add yourself. You can turn sharing on later.

Either way, CrowdSec downloads its detection rules from its hub." no
}

app_validate_options() {
  valid_yesno "$CROWDSEC_SHARING" || die "CROWDSEC_SHARING must be 'yes' or 'no'."
}

app_settings_text() {
  printf '%s\n' "Sharing:   ${CROWDSEC_SHARING} (signals to CrowdSec's Central API)"
}

app_summary_text() {
  local ip
  ip=$(ct_ip_only)
  say "  Local API: http://${ip}:8080 (for agents and bouncers on your network)"
  say "  Bouncer:   pct enter ${CT_ID}, then: cscli bouncers add <name>  (prints its API key)"
  say "  Agent:     on the other machine: cscli lapi register --url http://${ip}:8080"
  say "             then here: cscli machines validate <name>"
  if [[ "$CT_IP" == dhcp ]]; then
    say "  Note:      agents and bouncers point at this IP. Reserve ${ip} in your DHCP server."
  fi
}

app_notes_rows() {
  local ip
  ip=$(ct_ip_only)
  notes_row "Local API" "http://${ip}:8080, for agents and bouncers on your network"
  notes_row "Add a bouncer" "\`pct enter ${CT_ID}\` then \`cscli bouncers add NAME\`; it prints the API key the bouncer needs"
  notes_row "Add an agent" "on the other machine \`cscli lapi register --url http://${ip}:8080\`, then here \`cscli machines validate NAME\`"
  notes_row "Signal sharing" "${CROWDSEC_SHARING}"
}

if [[ -n "${RECIPES_SRC:-}" ]]; then
  # shellcheck source=/dev/null
  source "${RECIPES_SRC%/}/misc/build.func"
else
  engine=$(curl -fsSL --retry 2 --max-time 30 \
    "https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/${RECIPES_REF:-main}/misc/build.func") || {
    printf 'proxmox-recipes: could not download misc/build.func\n' >&2
    exit 1
  }
  # shellcheck source=/dev/null
  source /dev/stdin <<<"$engine"
fi

recipe_main
