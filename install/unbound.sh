# shellcheck shell=bash
#
# install/unbound.sh - Unbound, a validating, recursive, caching DNS resolver
# for the local network.
#
# Runs inside the container, sourced by misc/install.func. Follows NLnet
# Labs' official documentation:
#
#   Install:  https://unbound.docs.nlnetlabs.nl/en/latest/getting-started/installation.html
#             ("apt install unbound" from the distribution's package)
#   Config:   https://unbound.docs.nlnetlabs.nl/en/latest/getting-started/configuration.html
#             (the local-network example: "interface: 0.0.0.0" and
#             "access-control: <range> allow"; extended here to all three
#             private IPv4 ranges; checked with unbound-checkconf)
#
# Debian's package already enables DNSSEC validation (root trust anchor in
# /etc/unbound/unbound.conf.d/root-auto-trust-anchor-file.conf), and its
# unbound.conf includes every file in /etc/unbound/unbound.conf.d/.
#
# Unbound resolves by asking the DNS root servers directly, so the install
# first checks that the network allows that (the same tests as Pi-hole's
# Unbound guide, https://docs.pi-hole.net/guides/dns/unbound/).

# shellcheck disable=SC2034  # read by misc/install.func
{
  APP_PORTS="53/tcp 53/udp"
  APP_CONFIG="/etc/unbound/unbound.conf.d/recipe.conf"
}

UNBOUND_CONF="/etc/unbound/unbound.conf.d/recipe.conf"

app_install() {
  apt_quiet install --no-install-recommends bind9-dnsutils
  check_root_servers

  step "Installing Unbound"
  apt_quiet install unbound
  write_unbound_conf
  unbound-checkconf || fail "unbound-checkconf found an error in the config."
  systemctl enable unbound
  systemctl restart unbound
  check_unbound
}

# Unbound comes from Debian, so 'recipe update' has already upgraded it with
# the OS packages. Re-check the config and make sure it still answers.
app_update() {
  unbound-checkconf || fail "unbound-checkconf found an error in the config."
  systemctl restart unbound
  check_unbound
}

app_version() {
  unbound -V 2>/dev/null | awk '/^Version/ { print $2; exit }'
}

write_unbound_conf() {
  [[ -f "$UNBOUND_CONF" ]] && return 0   # never overwrite the user's config
  cat >"$UNBOUND_CONF" <<'EOF'
# Unbound for the local network, written by proxmox-recipes.
# Reference: https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html
# After editing: unbound-checkconf && systemctl restart unbound

server:
    # Answer queries on every interface.
    interface: 0.0.0.0
    port: 53

    # Only these networks may use this resolver (everything else is refused).
    access-control: 127.0.0.0/8 allow
    access-control: 10.0.0.0/8 allow
    access-control: 172.16.0.0/12 allow
    access-control: 192.168.0.0/16 allow

    do-ip4: yes
    do-udp: yes
    do-tcp: yes
    do-ip6: yes
    prefer-ip6: no

    # Do not tell clients the server's name or version.
    hide-identity: yes
    hide-version: yes

    # Keep popular names fresh in the cache.
    prefetch: yes

    # Do not let public names resolve to private addresses (DNS rebinding).
    private-address: 10.0.0.0/8
    private-address: 172.16.0.0/12
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: fd00::/8
    private-address: fe80::/10
EOF
  # No IPv6 connectivity -> do not try to reach servers over IPv6.
  if [[ -z "$(ip -6 route show default 2>/dev/null)" ]]; then
    sed -i 's/^    do-ip6: yes$/    do-ip6: no/' "$UNBOUND_CONF"
  fi
}

check_unbound() {
  local i status=""
  step "Testing Unbound"
  for (( i = 0; i < 15; i++ )); do
    status=$(dig_status nlnetlabs.nl @127.0.0.1 +time=3) || true
    [[ "$status" == NOERROR ]] && break
    sleep 2
  done
  [[ "$status" == NOERROR ]] || fail "Unbound does not answer on 127.0.0.1#53 (status: '${status}')."

  status=$(dig_status fail01.dnssec.works @127.0.0.1) || true
  [[ "$status" == SERVFAIL ]] || fail "Unbound is not validating DNSSEC: fail01.dnssec.works returned '${status}', expected SERVFAIL."

  has_flag "$(dig_flags +ad dnssec.works @127.0.0.1)" ad ||
    fail "Unbound is not validating DNSSEC: dnssec.works has no 'ad' flag."
}
