#!/usr/bin/env bash
#
# ct/rustdesk-server-pro.sh - RustDesk Server Pro: your own ID, relay and
# web console server for RustDesk remote desktop. Needs a RustDesk Server
# Pro licence, entered in the web console after install.
#
# Run on the Proxmox VE host as root:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/rustdesk-server-pro.sh)"
#
# From a local checkout (loads the engine from disk instead of GitHub):
#   RECIPES_SRC=/path/to/proxmox-recipes bash ct/rustdesk-server-pro.sh
#
# From another branch or tag on GitHub (default main):
#   RECIPES_REF=<branch> bash ct/rustdesk-server-pro.sh
#
# Clients outside your network need ports forwarded on your router (see
# docs/apps/rustdesk-server-pro.md): the recipe never changes router or
# host config.

set -Eeuo pipefail

# shellcheck disable=SC2034  # read by misc/build.func
{
  APP_NAME="RustDesk Server Pro"
  APP_SLUG="rustdesk-server-pro"
  APP_DEBIAN_RELEASE=13    # long-term server; Debian 12's regular support has ended
  APP_DEFAULT_HOSTNAME="rustdesk"
  APP_DEFAULT_CORES=2
  APP_DEFAULT_RAM_MB=1024
  APP_DEFAULT_DISK_GB=4
  APP_INSTALL_SCRIPT="install/rustdesk-server-pro.sh"
}

rd_ct_key() {
  pct exec "$CT_ID" -- cat /var/lib/rustdesk-server/id_ed25519.pub 2>/dev/null || true
}

app_summary_text() {
  say "  Login:     admin / test1234 (RustDesk's default). Change it right away."
  say "  Licence:   enter it in the web console. It binds to this server; to move"
  say "             it later, unbind it at https://rustdesk.com/self-host/account/"
  say "  Key:       $(rd_ct_key)"
  say "             Clients need this key and the server's address (ID server)."
  say "  Outside:   for clients outside your network, forward TCP 21115-21117"
  say "             and UDP 21116 on your router to this container."
}

app_notes_rows() {
  notes_row "Login" "admin / test1234 (RustDesk's default): change it right away"
  notes_row "Licence" "enter it in the web console. It binds to this server; unbind at https://rustdesk.com/self-host/account/ to move it"
  notes_row "Client key" "\`$(rd_ct_key)\`"
  notes_row "Client setup" "ID server: this container's address (or your public hostname). Key: the client key above"
  notes_row "Ports" "TCP 21114 web console; TCP 21115-21117 + UDP 21116 for clients (forward these for use outside your network); TCP 21118-21119 web client only"
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
