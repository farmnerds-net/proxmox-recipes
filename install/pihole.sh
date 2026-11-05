# shellcheck shell=bash
#
# install/pihole.sh - Pi-hole, with Unbound as an optional local recursive
# DNS resolver.
#
# Runs inside the container, sourced by misc/install.func. Every step
# follows Pi-hole's official documentation:
#
#   Install:  https://docs.pi-hole.net/main/basic-install/
#             ("Alternative 2: Manually download the installer and run")
#   Unbound:  https://docs.pi-hole.net/guides/dns/unbound/
#             (root server tests, pi-hole.conf, the Debian resolvconf fix,
#             the validation tests)
#   Upstream: https://docs.pi-hole.net/ftldns/configfile/
#             (dns.upstreams, set with 'pihole-FTL --config')
#   Commands: https://docs.pi-hole.net/main/pihole-command/
#             ('pihole -up' to update, 'pihole -v' for versions)
#
# Pi-hole's installer is interactive (it has no documented unattended
# mode), so ct/pihole.sh sets APP_INSTALL_INTERACTIVE=yes.
#
# App option, passed in from ct/pihole.sh:
#   PIHOLE_UNBOUND   yes | no

# shellcheck disable=SC2034  # read by misc/install.func
{
  APP_PORTS="53/tcp 53/udp 80/tcp 443/tcp"
  APP_CONFIG="/etc/pihole/pihole.toml; web password: 'pihole setpassword'"
}

UNBOUND_CONF="/etc/unbound/unbound.conf.d/pi-hole.conf"
ROOT_SERVER="198.41.0.4"   # a.root-servers.net, as used by the Unbound guide

app_install() {
  apt_quiet install --no-install-recommends wget
  cd /root || return
  wget -O basic-install.sh https://install.pi-hole.net
  bash basic-install.sh
  rm -f basic-install.sh

  if [[ "${PIHOLE_UNBOUND:-no}" == yes ]]; then
    unbound_install
  fi
}

app_update() {
  pihole -up
}

app_version() {
  local v
  v=$(pihole -v 2>/dev/null | awk '/ version is / { printf "%s%s %s", sep, $1, $4; sep = ", " }')
  if command -v unbound >/dev/null 2>&1; then
    v+=", Unbound $(unbound -V 2>/dev/null | awk '/^Version/ { print $2; exit }')"
  fi
  printf '%s' "${v:-unknown}"
}

# ---- Unbound (https://docs.pi-hole.net/guides/dns/unbound/) -----------------

dig_flags() {    # <dig args...> -> the header flags, e.g. "qr aa"
  dig "$@" | sed -n 's/^;; flags: \([^;]*\);.*/\1/p'
}

dig_status() {   # <dig args...> -> NOERROR, SERVFAIL, ...
  dig "$@" | sed -n 's/.*status: \([A-Z]*\),.*/\1/p'
}

has_flag() {     # <flags> <flag>
  [[ " $1 " == *" $2 "* ]]
}

# "Recommended: Test access to root servers". The guide says not to install
# Unbound if any of these fail.
check_root_servers() {
  local flags
  step "Checking direct access to the DNS root servers"

  flags=$(dig_flags @"$ROOT_SERVER" . NS +norec +time=3) || true
  if ! has_flag "$flags" aa || has_flag "$flags" ra; then
    fail "UDP DNS to the root servers is blocked or intercepted (flags: '${flags}'). Unbound will not work on this network; see https://docs.pi-hole.net/guides/dns/unbound/"
  fi

  flags=$(dig_flags @"$ROOT_SERVER" . NS +norec +tcp +time=3) || true
  if ! has_flag "$flags" aa || has_flag "$flags" ra; then
    fail "TCP DNS to the root servers is blocked or intercepted (flags: '${flags}'). Unbound will not work on this network; see https://docs.pi-hole.net/guides/dns/unbound/"
  fi

  if ! dig @"$ROOT_SERVER" version.bind CH TXT +time=3 | grep -q '"ATLAS"'; then
    fail "DNS to the root servers is being proxied (CHAOS check failed). Unbound will not work reliably on this network; see https://docs.pi-hole.net/guides/dns/unbound/"
  fi
}

write_unbound_conf() {
  # The guide's recommended /etc/unbound/unbound.conf.d/pi-hole.conf.
  cat >"$UNBOUND_CONF" <<'EOF'
server:
    # If no logfile is specified, syslog is used
    # logfile: "/var/log/unbound/unbound.log"
    verbosity: 0

    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-udp: yes
    do-tcp: yes

    # May be set to no if you don't have IPv6 connectivity
    do-ip6: yes

    # You want to leave this to no unless you have *native* IPv6. With 6to4 and
    # Terredo tunnels your web browser should favor IPv4 for the same reasons
    prefer-ip6: no

    # Use this only when you downloaded the list of primary root servers!
    # If you use the default dns-root-data package, unbound will find it automatically
    #root-hints: "/var/lib/unbound/root.hints"

    # Trust glue only if it is within the server's authority
    harden-glue: yes

    # Require DNSSEC data for trust-anchored zones, if such data is absent, the zone becomes BOGUS
    harden-dnssec-stripped: yes

    # Don't use Capitalization randomization as it known to cause DNSSEC issues sometimes
    # see https://discourse.pi-hole.net/t/unbound-stubby-or-dnscrypt-proxy/9378 for further details
    use-caps-for-id: no

    # Reduce EDNS reassembly buffer size.
    # IP fragmentation is unreliable on the Internet today, and can cause
    # transmission failures when large DNS messages are sent via UDP. Even
    # when fragmentation does work, it may not be secure; it is theoretically
    # possible to spoof parts of a fragmented DNS message, without easy
    # detection at the receiving end. Recently, there was an excellent study
    # >>> Defragmenting DNS - Determining the optimal maximum UDP response size for DNS <<<
    # by Axel Koolhaas, and Tjeerd Slokker (https://indico.dns-oarc.net/event/36/contributions/776/)
    # in collaboration with NLnet Labs explored DNS using real world data from the
    # the RIPE Atlas probes and the researchers suggested different values for
    # IPv4 and IPv6 and in different scenarios. They advise that servers should
    # be configured to limit DNS messages sent over UDP to a size that will not
    # trigger fragmentation on typical network links. DNS servers can switch
    # from UDP to TCP when a DNS response is too big to fit in this limited
    # buffer size. This value has also been suggested in DNS Flag Day 2020.
    edns-buffer-size: 1232

    # Perform prefetching of close to expired message cache entries
    # This only applies to domains that have been frequently queried
    prefetch: yes

    # One thread should be sufficient, can be increased on beefy machines. In reality for most users running on small networks or on a single machine, it should be unnecessary to seek performance enhancement by increasing num-threads above 1.
    num-threads: 1

    # Ensure kernel buffer is large enough to not lose messages in traffic spikes
    so-rcvbuf: 1m

    # Ensure privacy of local IP ranges
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10

    # Ensure no reverse queries to non-public IP ranges (RFC6303 4.2)
    private-address: 192.0.2.0/24
    private-address: 198.51.100.0/24
    private-address: 203.0.113.0/24
    private-address: 255.255.255.255/32
    private-address: 2001:db8::/32
EOF
  # As the comment above says: no IPv6 connectivity -> do-ip6: no.
  if [[ -z "$(ip -6 route show default 2>/dev/null)" ]]; then
    sed -i 's/^    do-ip6: yes$/    do-ip6: no/' "$UNBOUND_CONF"
  fi
}

# "Disable resolvconf.conf entry for unbound (Required for Debian
# Bullseye+ releases)".
unbound_resolvconf_fix() {
  if systemctl list-unit-files unbound-resolvconf.service >/dev/null 2>&1; then
    systemctl disable --now unbound-resolvconf.service
  fi
  if [[ -f /etc/resolvconf.conf ]]; then
    sed -Ei 's/^unbound_conf=/#unbound_conf=/' /etc/resolvconf.conf
  fi
  rm -f /etc/unbound/unbound.conf.d/resolvconf_resolvers.conf
}

# "Start your local recursive server and test that it's operational" and
# "Test validation".
check_unbound() {
  local i status=""
  step "Testing Unbound"
  for (( i = 0; i < 10; i++ )); do
    status=$(dig_status pi-hole.net @127.0.0.1 -p 5335) || true
    [[ "$status" == NOERROR ]] && break
    sleep 2
  done
  [[ "$status" == NOERROR ]] || fail "Unbound does not answer on 127.0.0.1#5335 (status: '${status}')."

  status=$(dig_status fail01.dnssec.works @127.0.0.1 -p 5335) || true
  [[ "$status" == SERVFAIL ]] || fail "Unbound is not validating DNSSEC: fail01.dnssec.works returned '${status}', expected SERVFAIL."

  has_flag "$(dig_flags +ad dnssec.works @127.0.0.1 -p 5335)" ad ||
    fail "Unbound is not validating DNSSEC: dnssec.works has no 'ad' flag."
}

unbound_install() {
  apt_quiet install --no-install-recommends bind9-dnsutils
  check_root_servers

  step "Installing Unbound"
  apt_quiet install unbound
  write_unbound_conf
  unbound_resolvconf_fix
  systemctl restart unbound
  check_unbound

  # "Configure Pi-hole": 127.0.0.1#5335 as the only upstream.
  step "Pointing Pi-hole at Unbound"
  pihole-FTL --config dns.upstreams '[ "127.0.0.1#5335" ]'
}
