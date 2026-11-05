#!/usr/bin/env bash
#
# ct/pihole.sh - Pi-hole network-wide ad blocking, with Unbound as an
# optional local recursive DNS resolver.
#
# Pi-hole's official installer asks its own questions, so run this from an
# interactive shell on the Proxmox VE host as root:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/pihole.sh)"
#
# From a local checkout (loads the engine from disk instead of GitHub):
#   RECIPES_SRC=/path/to/proxmox-recipes bash ct/pihole.sh
#
# App option (preset it to skip the question):
#   PIHOLE_UNBOUND   yes | no   install Unbound and use it as Pi-hole's upstream

set -Eeuo pipefail

# shellcheck disable=SC2034  # read by misc/build.func
{
  APP_NAME="Pi-hole"
  APP_SLUG="pihole"
  APP_DEBIAN_RELEASE=12
  APP_DEFAULT_HOSTNAME="pihole"
  APP_DEFAULT_CORES=1
  APP_DEFAULT_RAM_MB=512   # Pi-hole prerequisites: 512 MB RAM
  APP_DEFAULT_DISK_GB=4    # Pi-hole prerequisites: 2 GB min, 4 GB recommended
  APP_INSTALL_SCRIPT="install/pihole.sh"
  APP_INSTALL_INTERACTIVE=yes
  APP_ENV_VARS=(PIHOLE_UNBOUND)
}

app_ask_options() {
  ui_yesno PIHOLE_UNBOUND "Also install Unbound?

Unbound is a recursive DNS resolver that runs inside the container. Pi-hole then asks the DNS root servers directly instead of a public resolver such as Google or Cloudflare.

This follows Pi-hole's official Unbound guide. It needs direct access to the root servers on port 53 (UDP and TCP); the install checks this first.

If you say yes, pick any upstream DNS in Pi-hole's installer: it is replaced with Unbound afterwards." no
}

app_validate_options() {
  valid_yesno "$PIHOLE_UNBOUND" || die "PIHOLE_UNBOUND must be 'yes' or 'no'."
}

app_settings_text() {
  printf '%s\n' "Unbound:   ${PIHOLE_UNBOUND}"
}

app_summary_text() {
  local ip
  ip=$(ct_ip_only)
  say "  Password:  shown at the end of Pi-hole's installer; to change it: pct enter ${CT_ID}, then: pihole setpassword"
  if [[ "$CT_IP" == dhcp ]]; then
    say "  Note:      Pi-hole should keep the same IP. Reserve ${ip} for this container in your DHCP server."
  fi
}

app_notes_rows() {
  if [[ "$PIHOLE_UNBOUND" == yes ]]; then
    notes_row "Unbound" "yes: Pi-hole resolves through Unbound on 127.0.0.1#5335"
  else
    notes_row "Unbound" "no"
  fi
  notes_row "Web password" "shown at the end of the install; to change it: \`pct enter ${CT_ID}\` then \`pihole setpassword\`"
  notes_row "Use it" "set $(ct_ip_only) as the DNS server in your router's DHCP settings"
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
