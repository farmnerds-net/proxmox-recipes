# shellcheck shell=bash
#
# install/coredns.sh - CoreDNS, a DNS server built from plugins.
#
# Runs inside the container, sourced by misc/install.func. Follows CoreDNS's
# official documentation and the CoreDNS project's own deployment files:
#
#   Install:  https://coredns.io/manual/toc/#installation
#             (the pre-compiled release binaries from
#             https://github.com/coredns/coredns/releases, checked against
#             each release's .sha256 file)
#   Service:  https://github.com/coredns/deployment/tree/master/systemd
#             (coredns.service, coredns-sysusers.conf, coredns-tmpfiles.conf
#             and coredns-log.conf, installed where its README says)
#   Config:   https://coredns.io/manual/toc/#configuration
#             (a Corefile with the forward and cache plugins)

# shellcheck disable=SC2034  # read by misc/install.func
{
  APP_PORTS="53/tcp 53/udp"
  APP_CONFIG="/etc/coredns/Corefile"
}

COREDNS_BIN="/usr/bin/coredns"
COREDNS_CONF="/etc/coredns/Corefile"
COREDNS_API="https://api.github.com/repos/coredns/coredns/releases/latest"
COREDNS_DEPLOY="https://raw.githubusercontent.com/coredns/deployment/master/systemd"

app_install() {
  apt_quiet install --no-install-recommends bind9-dnsutils logrotate
  coredns_fetch "$(coredns_latest_tag)"
  coredns_deploy_files
  systemd-sysusers coredns-sysusers.conf
  systemd-tmpfiles --create coredns-tmpfiles.conf
  write_corefile
  systemctl daemon-reload
  systemctl enable --now coredns
  check_coredns
}

app_update() {
  local latest current
  latest=$(coredns_latest_tag)
  current=$(app_version)
  if [[ "v${current}" == "$latest" ]]; then
    msg "CoreDNS ${current} is already the latest release."
    return 0
  fi
  step "Updating CoreDNS ${current} -> ${latest#v}"
  coredns_fetch "$latest"
  systemctl restart coredns
  check_coredns
}

app_version() {
  # 'coredns -version' prints e.g. "CoreDNS-1.15.0" on its first line.
  "$COREDNS_BIN" -version 2>/dev/null | sed -n '1s/^CoreDNS-//p'
}

coredns_latest_tag() {
  local tag
  tag=$(curl -fsSL --retry 2 --max-time 30 "$COREDNS_API" |
    sed -n 's/^ *"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)
  [[ "$tag" =~ ^v[0-9]+(\.[0-9]+)+$ ]] || fail "Could not find CoreDNS's latest release on GitHub."
  printf '%s' "$tag"
}

coredns_arch() {
  case "$(dpkg --print-architecture)" in
    amd64) printf 'amd64' ;;
    arm64) printf 'arm64' ;;
    armhf) printf 'arm' ;;
    *) fail "No CoreDNS release for architecture $(dpkg --print-architecture)." ;;
  esac
}

coredns_fetch() {   # <tag>: download, verify and install that release's binary
  local tag=$1 tmp pkg base
  pkg="coredns_${tag#v}_linux_$(coredns_arch).tgz"
  base="https://github.com/coredns/coredns/releases/download/${tag}"
  tmp=$(mktemp -d)
  step "Downloading CoreDNS ${tag#v}"
  curl -fsSL --retry 2 --max-time 120 -o "${tmp}/${pkg}" "${base}/${pkg}"
  curl -fsSL --retry 2 --max-time 30 -o "${tmp}/${pkg}.sha256" "${base}/${pkg}.sha256"
  ( cd "$tmp" && sha256sum -c --quiet "${pkg}.sha256" ) ||
    { rm -rf "$tmp"; fail "Checksum mismatch for ${pkg}; not installing it."; }
  tar -C "$tmp" -xzf "${tmp}/${pkg}" coredns
  install -m 0755 "${tmp}/coredns" "$COREDNS_BIN"
  rm -rf "$tmp"
}

# The files from github.com/coredns/deployment/systemd, where its README
# says to put them.
coredns_deploy_files() {
  step "Installing the CoreDNS project's systemd files"
  curl -fsSL --retry 2 --max-time 30 -o /etc/systemd/system/coredns.service "${COREDNS_DEPLOY}/coredns.service"
  curl -fsSL --retry 2 --max-time 30 -o /usr/lib/sysusers.d/coredns-sysusers.conf "${COREDNS_DEPLOY}/coredns-sysusers.conf"
  curl -fsSL --retry 2 --max-time 30 -o /usr/lib/tmpfiles.d/coredns-tmpfiles.conf "${COREDNS_DEPLOY}/coredns-tmpfiles.conf"
  curl -fsSL --retry 2 --max-time 30 -o /etc/logrotate.d/coredns "${COREDNS_DEPLOY}/coredns-log.conf"
  grep -q '^ExecStart=' /etc/systemd/system/coredns.service ||
    fail "Downloaded coredns.service does not look like a systemd unit."
}

write_corefile() {
  [[ -f "$COREDNS_CONF" ]] && return 0   # never overwrite the user's config
  install -d -m 0755 "$(dirname "$COREDNS_CONF")"
  cat >"$COREDNS_CONF" <<'EOF'
# CoreDNS configuration, written by proxmox-recipes.
# Reference: https://coredns.io/manual/toc/  Plugins: https://coredns.io/plugins/
# After editing: systemctl restart coredns

.:53 {
    # Send every query to these upstream DNS servers.
    # (Running the Unbound recipe? Put its IP here instead.)
    forward . 1.1.1.1 9.9.9.9
    cache
    errors
    # Uncomment to log every query to /var/log/coredns.log:
    # log
}
EOF
  chmod 0644 "$COREDNS_CONF"
}

check_coredns() {
  local i status=""
  step "Testing CoreDNS"
  for (( i = 0; i < 15; i++ )); do
    if systemctl is-active --quiet coredns; then
      status=$(dig example.com @127.0.0.1 +time=2 | sed -n 's/.*status: \([A-Z]*\),.*/\1/p') || true
      [[ "$status" == NOERROR ]] && return 0
    fi
    sleep 2
  done
  tail -n 20 /var/log/coredns.err.log >&2 2>/dev/null || true
  fail "CoreDNS does not answer on 127.0.0.1#53 (status: '${status}')."
}
