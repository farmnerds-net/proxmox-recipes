# shellcheck shell=bash
#
# install/caddy.sh - Caddy, a web server and reverse proxy with automatic
# HTTPS.
#
# Runs inside the container, sourced by misc/install.func. Follows Caddy's
# official documentation:
#
#   Install:  https://caddyserver.com/docs/install#debian-ubuntu-raspbian
#             (stable releases: debian-keyring, debian-archive-keyring,
#             apt-transport-https, the Cloudsmith gpg.key dearmored to
#             /usr/share/keyrings/caddy-stable-archive-keyring.gpg, the
#             repository list from debian.deb.txt, both made world-readable,
#             then 'apt install caddy')
#   Service:  https://caddyserver.com/docs/running#using-the-service
#             (the package runs the 'caddy' systemd service from
#             /etc/caddy/Caddyfile; change it with 'systemctl reload caddy')
#
# The packaged Caddyfile serves a welcome page on port 80. The recipe keeps
# it, so the user starts from upstream's own example.

# shellcheck disable=SC2034  # read by misc/install.func
{
  APP_PORTS="80/tcp, 443/tcp and 443/udp (sites), 2019 on 127.0.0.1 only (admin API)"
  APP_CONFIG="/etc/caddy/Caddyfile (after editing: systemctl reload caddy)"
}

CADDY_KEYRING="/usr/share/keyrings/caddy-stable-archive-keyring.gpg"
CADDY_LIST="/etc/apt/sources.list.d/caddy-stable.list"
CADDY_REPO="https://dl.cloudsmith.io/public/caddy/stable"
CADDY_CONF="/etc/caddy/Caddyfile"

app_install() {
  step "Adding Caddy's apt repository (stable)"
  apt_quiet install --no-install-recommends debian-keyring debian-archive-keyring apt-transport-https gnupg
  curl -fsSL --retry 2 --max-time 30 "${CADDY_REPO}/gpg.key" | gpg --dearmor --yes -o "$CADDY_KEYRING"
  curl -fsSL --retry 2 --max-time 30 -o "$CADDY_LIST" "${CADDY_REPO}/debian.deb.txt"
  chmod o+r "$CADDY_KEYRING" "$CADDY_LIST"
  grep -q "signed-by=${CADDY_KEYRING}" "$CADDY_LIST" ||
    fail "Caddy's repository list does not use ${CADDY_KEYRING}; its layout has changed."
  apt_quiet update
  step "Installing Caddy"
  apt_quiet install caddy
  check_caddy
}

# Caddy comes from its apt repository, so 'recipe update' has already
# upgraded it with the OS packages (which restarts the service and keeps
# the user's Caddyfile). Check that it is still serving.
app_update() {
  step "Checking the Caddyfile"
  caddy validate --config "$CADDY_CONF" --adapter caddyfile
  check_caddy
}

app_web() {
  printf 'http 80 /\n'
}

app_version() {
  # 'caddy version' prints e.g. "v2.10.2 h1:...".
  caddy version 2>/dev/null | awk '{ sub(/^v/, "", $1); print $1; exit }'
}

check_caddy() {
  local i
  step "Waiting for Caddy to start"
  for (( i = 0; i < 30; i++ )); do
    if systemctl is-active --quiet caddy &&
      curl -fs -o /dev/null --max-time 3 http://127.0.0.1:2019/config/; then
      return 0
    fi
    sleep 2
  done
  journalctl -u caddy -n 20 --no-pager >&2 || true
  fail "Caddy did not start."
}
