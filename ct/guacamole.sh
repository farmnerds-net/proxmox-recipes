#!/usr/bin/env bash
#
# ct/guacamole.sh - Apache Guacamole: a clientless remote desktop gateway.
# Use RDP, VNC and SSH connections from a web browser, with users and
# connections stored in PostgreSQL.
#
# Run on the Proxmox VE host as root:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/guacamole.sh)"
#
# From a local checkout (loads the engine from disk instead of GitHub):
#   RECIPES_SRC=/path/to/proxmox-recipes bash ct/guacamole.sh
#
# From another branch or tag on GitHub (default main):
#   RECIPES_REF=<branch> bash ct/guacamole.sh

set -Eeuo pipefail

# shellcheck disable=SC2034  # read by misc/build.func
{
  APP_NAME="Apache Guacamole"
  APP_SLUG="guacamole"
  APP_DEBIAN_RELEASE=12    # FreeRDP 2.x: guacamole-server 1.6.0 does not build against Debian 13's FreeRDP 3
  APP_DEFAULT_HOSTNAME="guacamole"
  APP_DEFAULT_CORES=2      # guacamole-server is compiled during install and on updates
  APP_DEFAULT_RAM_MB=2048
  APP_DEFAULT_DISK_GB=8
  APP_INSTALL_SCRIPT="install/guacamole.sh"
}

guac_ct_admin_pw() {
  pct exec "$CT_ID" -- cat /root/guacadmin-password 2>/dev/null || true
}

app_summary_text() {
  say "  Login:     guacadmin / $(guac_ct_admin_pw)"
  say "             (random; also in /root/guacadmin-password in the container)"
  say "  Install:   guacamole-server was compiled from source; updates rebuild it."
}

# The password itself stays out of the Notes, which every Proxmox user
# who can see the container can read.
app_notes_rows() {
  notes_row "Login" "guacadmin; its random first password is in \`/root/guacadmin-password\` (\`pct exec ${CT_ID} -- cat /root/guacadmin-password\`). Change it, or make your own admin and delete guacadmin"
  notes_row "Connections" "Settings > Connections > New Connection (RDP, VNC, SSH, Telnet)"
  notes_row "Config" "\`/etc/guacamole/guacamole.properties\`; users and connections in PostgreSQL \`guacamole_db\`"
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
