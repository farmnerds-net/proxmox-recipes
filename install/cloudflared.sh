# shellcheck shell=bash
#
# install/cloudflared.sh - cloudflared, the connector for Cloudflare Tunnel.
#
# Runs inside the container, sourced by misc/install.func. Follows
# Cloudflare's official documentation:
#
#   Install:  https://pkg.cloudflare.com/index.html  (Debian Bookworm: the
#             cloudflare-main.gpg key in /usr/share/keyrings, the
#             'pkg.cloudflare.com/cloudflared bookworm main' repository,
#             then 'apt-get install cloudflared')
#   Connect:  https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/create-remote-tunnel/
#             (create the tunnel in the dashboard, then run the install
#             command it shows on the server)
#
# The recipe only installs cloudflared. Connecting it needs the tunnel
# token, a secret, which the user pastes in inside the container
# ('cloudflared service install <token>'), so it never passes through the
# recipe, its logs or the host's process list.

# shellcheck disable=SC2034  # read by misc/install.func
{
  APP_PORTS="none inbound (outbound connections to Cloudflare only)"
  APP_CONFIG="the tunnel's settings live in the Cloudflare dashboard (Networking > Tunnels)"
}

CF_KEYRING="/usr/share/keyrings/cloudflare-main.gpg"
CF_KEY_URL="https://pkg.cloudflare.com/cloudflare-main.gpg"

app_install() {
  local codename
  codename=$(sed -n 's/^VERSION_CODENAME=//p' /etc/os-release)
  step "Adding Cloudflare's apt repository (${codename})"
  curl -fsSL --retry 2 --max-time 30 -o "$CF_KEYRING" "$CF_KEY_URL"
  printf 'deb [signed-by=%s] https://pkg.cloudflare.com/cloudflared %s main\n' \
    "$CF_KEYRING" "$codename" >/etc/apt/sources.list.d/cloudflared.list
  apt_quiet update
  step "Installing cloudflared"
  apt_quiet install cloudflared
  cloudflared --version >/dev/null || fail "cloudflared did not install correctly."
}

# cloudflared comes from Cloudflare's apt repository, so 'recipe update' has
# already upgraded it with the OS packages. Restart the tunnel, if one is
# connected, so it runs the new version.
app_update() {
  if systemctl list-unit-files cloudflared.service >/dev/null 2>&1 &&
    systemctl is-enabled --quiet cloudflared 2>/dev/null; then
    step "Restarting the tunnel"
    systemctl restart cloudflared
  else
    msg "No tunnel is connected yet; nothing to restart."
  fi
}

app_version() {
  # 'cloudflared --version' prints e.g. "cloudflared version 2025.11.1 (built ...)".
  cloudflared --version 2>/dev/null | awk '{ print $3; exit }'
}
