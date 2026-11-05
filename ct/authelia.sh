#!/usr/bin/env bash
#
# ct/authelia.sh - Authelia, single sign-on and two-factor authentication
# for the apps behind your reverse proxy.
#
# Run on the Proxmox VE host as root:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/authelia.sh)"
#
# From a local checkout (loads the engine from disk instead of GitHub):
#   RECIPES_SRC=/path/to/proxmox-recipes bash ct/authelia.sh
#
# From another branch or tag on GitHub (default main):
#   RECIPES_REF=<branch> bash ct/authelia.sh
#
# Option (preset it to skip the question):
#   AUTHELIA_URL=https://auth.example.com   the portal's public HTTPS URL
#
# Authelia only works over HTTPS on a real domain, so it needs a reverse
# proxy in front of it; the recipe does not set one up.

set -Eeuo pipefail

# shellcheck disable=SC2034  # read by misc/build.func
{
  APP_NAME="Authelia"
  APP_SLUG="authelia"
  APP_DEBIAN_RELEASE=12
  APP_DEFAULT_HOSTNAME="authelia"
  APP_DEFAULT_CORES=1
  APP_DEFAULT_RAM_MB=512
  APP_DEFAULT_DISK_GB=2
  APP_INSTALL_SCRIPT="install/authelia.sh"
  APP_ENV_VARS=(AUTHELIA_URL)
}

# https://<host with at least one dot>[/path], not an IP address or localhost.
valid_authelia_url() {
  local host
  [[ "$1" =~ ^https://([A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+)(/[A-Za-z0-9._~/-]*)?$ ]] || return 1
  host=${BASH_REMATCH[1]}
  [[ ! "$host" =~ ^[0-9.]+$ ]] || return 1
  [[ "$host" != localhost && "$host" != *.localhost ]]
}

app_ask_options() {
  ui_input AUTHELIA_URL "Authelia portal URL

The HTTPS address people will log in at, on your own domain, e.g. https://auth.example.com. Your reverse proxy must serve it over HTTPS. Authelia does not work on an IP address, on http://, or on a bare public suffix such as duckdns.org." \
    "https://auth.example.com" valid_authelia_url \
    "Enter an https:// URL on a real domain, e.g. https://auth.example.com (no IP addresses, no port)."
}

app_validate_options() {
  valid_authelia_url "$AUTHELIA_URL" || die "AUTHELIA_URL must be an https:// URL on a real domain, e.g. https://auth.example.com."
}

app_settings_text() {
  printf '%s\n' "Portal:    ${AUTHELIA_URL}"
}

app_summary_text() {
  local ip
  ip=$(ct_ip_only)
  say "  Proxy:     point ${AUTHELIA_URL} at http://${ip}:9091 in your HTTPS reverse proxy"
  say "  Login:     admin; password: pct exec ${CT_ID} -- cat /root/authelia-admin-password"
  say "  Codes:     2FA setup codes go to /var/lib/authelia/notification.txt (no email set up)"
}

app_notes_rows() {
  local ip
  ip=$(ct_ip_only)
  notes_row "Portal" "${AUTHELIA_URL}, served by your HTTPS reverse proxy from http://${ip}:9091"
  notes_row "Admin login" "user \`admin\`; password: \`pct exec ${CT_ID} -- cat /root/authelia-admin-password\`"
  notes_row "Email" "not set up: 2FA and reset codes are written to \`/var/lib/authelia/notification.txt\`"
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
