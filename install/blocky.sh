# shellcheck shell=bash
#
# install/blocky.sh - Blocky, a DNS proxy and ad blocker.
#
# Runs inside the container, sourced by misc/install.func. Follows Blocky's
# official documentation:
#
#   Install:  https://0xerr0r.github.io/blocky/latest/installation/
#             ("Download the binary file from GitHub for your architecture
#             and run ./blocky --config config.yml"), from the official
#             releases at https://github.com/0xERR0R/blocky/releases,
#             checked against the release's blocky_checksums.txt
#   Port 53:  same page: bind port 53 as a non-root user with
#             NET_BIND_SERVICE (running as root "not recommended"); the
#             systemd unit grants it as an ambient capability
#   Config:   https://0xerr0r.github.io/blocky/latest/configuration/
#             (upstreams.groups, blocking.denylists / clientGroupsBlock,
#             ports; the StevenBlack list is the docs' own example)
#
# Blocky has no built-in web UI: port 4000 serves its REST API, metrics
# and DNS-over-HTTPS. Settings live in /etc/blocky/config.yml.

# shellcheck disable=SC2034  # read by misc/install.func
{
  APP_PORTS="53/tcp 53/udp 4000/tcp (API)"
  APP_CONFIG="/etc/blocky/config.yml"
}

BLOCKY_BIN="/usr/local/bin/blocky"
BLOCKY_CONF_DIR="/etc/blocky"
BLOCKY_CONF="${BLOCKY_CONF_DIR}/config.yml"
BLOCKY_UNIT="/etc/systemd/system/blocky.service"
BLOCKY_USER="blocky"
BLOCKY_API="https://api.github.com/repos/0xERR0R/blocky/releases/latest"

app_install() {
  blocky_fetch "$(blocky_latest_tag)"
  id "$BLOCKY_USER" >/dev/null 2>&1 ||
    useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin "$BLOCKY_USER"
  write_blocky_conf
  write_blocky_unit
  systemctl daemon-reload
  systemctl enable --now blocky
  check_blocky
}

app_update() {
  local latest current
  latest=$(blocky_latest_tag)
  current=$(app_version)
  if [[ "$current" == "$latest" ]]; then
    msg "Blocky ${current} is already the latest release."
    return 0
  fi
  step "Updating Blocky ${current} -> ${latest}"
  blocky_fetch "$latest"
  systemctl restart blocky
  check_blocky
}

app_version() {
  # 'blocky version' prints e.g. "Version: v0.35.0".
  "$BLOCKY_BIN" version 2>/dev/null | awk '/^Version:/ { print $2; exit }'
}

blocky_latest_tag() {
  local tag
  tag=$(curl -fsSL --retry 2 --max-time 30 "$BLOCKY_API" |
    sed -n 's/^ *"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)
  [[ "$tag" =~ ^v[0-9]+(\.[0-9]+)+$ ]] || fail "Could not find Blocky's latest release on GitHub."
  printf '%s' "$tag"
}

blocky_arch() {
  case "$(dpkg --print-architecture)" in
    amd64) printf 'x86_64' ;;
    arm64) printf 'arm64' ;;
    armhf) printf 'armv7' ;;
    *) fail "No Blocky release for architecture $(dpkg --print-architecture)." ;;
  esac
}

blocky_fetch() {   # <tag>: download, verify and install that release's binary
  local tag=$1 tmp pkg base
  pkg="blocky_${tag}_Linux_$(blocky_arch).tar.gz"
  base="https://github.com/0xERR0R/blocky/releases/download/${tag}"
  tmp=$(mktemp -d)
  step "Downloading Blocky ${tag}"
  curl -fsSL --retry 2 --max-time 120 -o "${tmp}/${pkg}" "${base}/${pkg}"
  curl -fsSL --retry 2 --max-time 30 -o "${tmp}/checksums.txt" "${base}/blocky_checksums.txt"
  ( cd "$tmp" && grep " ${pkg}\$" checksums.txt | sha256sum -c --quiet - ) ||
    { rm -rf "$tmp"; fail "Checksum mismatch for ${pkg}; not installing it."; }
  tar -C "$tmp" -xzf "${tmp}/${pkg}" blocky
  install -m 0755 "${tmp}/blocky" "$BLOCKY_BIN"
  rm -rf "$tmp"
}

write_blocky_conf() {
  [[ -f "$BLOCKY_CONF" ]] && return 0   # never overwrite the user's config
  install -d -m 0755 "$BLOCKY_CONF_DIR"
  cat >"$BLOCKY_CONF" <<'EOF'
# Blocky configuration. Reference:
#   https://0xerr0r.github.io/blocky/latest/configuration/
# After editing: systemctl restart blocky

upstreams:
  groups:
    default:
      - 1.1.1.1   # Cloudflare
      - 9.9.9.9   # Quad9

blocking:
  denylists:
    ads:
      - https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
  clientGroupsBlock:
    default:
      - ads

ports:
  dns: 53
  http: 4000
EOF
  chmod 0644 "$BLOCKY_CONF"
}

write_blocky_unit() {
  cat >"$BLOCKY_UNIT" <<EOF
[Unit]
Description=Blocky DNS proxy and ad blocker
Documentation=https://0xerr0r.github.io/blocky/
After=network-online.target
Wants=network-online.target

[Service]
User=${BLOCKY_USER}
Group=${BLOCKY_USER}
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=yes
ExecStart=${BLOCKY_BIN} --config ${BLOCKY_CONF}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

check_blocky() {
  local i
  step "Waiting for Blocky to listen on port 53"
  # Blocky loads its lists before it opens the DNS port.
  for (( i = 0; i < 60; i++ )); do
    if systemctl is-active --quiet blocky && ss -Hlnu 'sport = :53' | grep -q .; then
      return 0
    fi
    sleep 1
  done
  journalctl -u blocky -n 20 --no-pager >&2 || true
  fail "Blocky did not start listening on port 53; see the log above."
}
