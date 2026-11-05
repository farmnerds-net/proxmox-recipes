#!/usr/bin/env bash
#
# ct/documenso.sh - Documenso, an open-source document signing app.
#
# Run on the Proxmox VE host as root:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/documenso.sh)"
#
# From a local checkout (loads the engine from disk instead of GitHub):
#   RECIPES_SRC=/path/to/proxmox-recipes bash ct/documenso.sh
#
# From another branch or tag on GitHub (default main):
#   RECIPES_REF=<branch> bash ct/documenso.sh
#
# Documenso is built from source, as its manual deployment guide describes,
# so the install takes a while and needs more memory than the app does once
# it runs. The recipe does not ask for SMTP settings: the password is a
# secret, and app options reach the container on the pct exec command line,
# which other users on the host can see. They go in the .env afterwards.

set -Eeuo pipefail

# shellcheck disable=SC2034  # read by misc/build.func
{
  APP_NAME="Documenso"
  APP_SLUG="documenso"
  APP_DEBIAN_RELEASE=12
  APP_DEFAULT_HOSTNAME="documenso"
  APP_DEFAULT_CORES=4      # the build is the slow part; the app needs less
  APP_DEFAULT_RAM_MB=4096  # the build needs it; the app runs in well under 1 GB
  APP_DEFAULT_DISK_GB=16   # source, node_modules and a second copy during updates
  APP_INSTALL_SCRIPT="install/documenso.sh"
}

app_summary_text() {
  say "  Email:     not set up yet. Documenso needs SMTP to send signing requests:"
  say "             pct enter ${CT_ID}, edit /var/www/documenso/.env (NEXT_PRIVATE_SMTP_*),"
  say "             then: systemctl restart documenso"
  say "  Account:   sign up in the web UI; the first account is yours."
}

app_notes_rows() {
  notes_row "Email (SMTP)" "not set up: \`pct enter ${CT_ID}\`, set the \`NEXT_PRIVATE_SMTP_*\` lines in \`/var/www/documenso/.env\`, then \`systemctl restart documenso\`"
  notes_row "Public URL" "\`NEXT_PUBLIC_WEBAPP_URL\` in the same file must be the address you open Documenso at, or sign-in fails with Forbidden; change it if you use a domain or tunnel"
  notes_row "Signing certificate" "self-signed, in \`/etc/documenso/cert.p12\`; PDF readers show signatures as not trusted"
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
