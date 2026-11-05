# shellcheck shell=bash
#
# install/powerdns.sh - PowerDNS Recursor and Authoritative Server in one
# container: the Recursor answers the network on port 53 and forwards the
# local zone (home.arpa) to the Authoritative Server on 127.0.0.1:5300,
# which stores its zones in SQLite.
#
# Runs inside the container, sourced by misc/install.func. Follows PowerDNS's
# official documentation:
#
#   Install:  https://repo.powerdns.com/  (the official Debian 12 apt
#             repositories bookworm-auth-51 and bookworm-rec-54, their
#             signing key and pin file, then 'apt-get install pdns-server'
#             and 'pdns-recursor')
#   Auth DB:  https://doc.powerdns.com/authoritative/backends/generic-sqlite3.html
#             (launch=gsqlite3, gsqlite3-database; schema from the
#             pdns-backend-sqlite3 package)
#   Auth API: https://doc.powerdns.com/authoritative/http-api/index.html
#             (api, api-key, webserver-address/-port/-allow-from)
#   Recursor: https://doc.powerdns.com/recursor/yamlsettings.html
#             (incoming.listen / allow_from, recursor.forward_zones,
#             dnssec.negative_trustanchors), in the packaged include_dir
#   Zones:    https://doc.powerdns.com/authoritative/manpages/pdnsutil.1.html
#             ('pdnsutil zone create', 'pdnsutil rrset add')
#
# home.arpa is the name RFC 8375 reserves for home networks.

# shellcheck disable=SC2034  # read by misc/install.func
{
  APP_PORTS="53/tcp 53/udp (Recursor), 8081/tcp (Authoritative API), 5300 on 127.0.0.1 only (Authoritative)"
  APP_CONFIG="/etc/powerdns/recursor.d/recipe.yml, /etc/powerdns/pdns.d/recipe.conf (API key), /var/lib/powerdns/pdns.sqlite3 (zones)"
}

PDNS_AUTH_SERIES="51"   # Authoritative Server 5.1.x, current stable
PDNS_REC_SERIES="54"    # Recursor 5.4.x, current stable
PDNS_KEY_URL="https://repo.powerdns.com/FD380FBB-pub.asc"
PDNS_KEYRING="/etc/apt/keyrings/pdns-pub.asc"
PDNS_ZONE="home.arpa"
PDNS_DB="/var/lib/powerdns/pdns.sqlite3"
PDNS_SCHEMA="/usr/share/doc/pdns-backend-sqlite3/schema.sqlite3.sql"
PDNS_AUTH_CONF="/etc/powerdns/pdns.d/recipe.conf"
PDNS_REC_CONF="/etc/powerdns/recursor.d/recipe.yml"
PRIVATE_NETS="127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

app_install() {
  apt_quiet install --no-install-recommends bind9-dnsutils sqlite3
  add_pdns_repos
  step "Installing PowerDNS Authoritative Server and Recursor"
  apt_quiet update
  apt_quiet install pdns-server pdns-backend-sqlite3 pdns-recursor

  write_auth_conf
  create_auth_db
  write_recursor_conf
  systemctl enable pdns pdns-recursor
  systemctl restart pdns
  create_local_zone
  systemctl restart pdns-recursor
  check_powerdns
}

# Both come from the PowerDNS apt repositories, so 'recipe update' has
# already upgraded them with the OS packages. Make sure they still answer.
app_update() {
  systemctl restart pdns pdns-recursor
  check_powerdns
}

app_version() {
  local auth rec
  auth=$(pdns_server --version 2>&1 | sed -n 's/.*PowerDNS Authoritative Server \([^ ]*\).*/\1/p' | head -n 1)
  rec=$(pdns_recursor --version 2>&1 | sed -n 's/.*PowerDNS Recursor \([^ ]*\).*/\1/p' | head -n 1)
  printf 'Recursor %s, Authoritative %s' "${rec:-unknown}" "${auth:-unknown}"
}

# ---- install steps ----------------------------------------------------------

add_pdns_repos() {
  local codename
  codename=$(sed -n "s/^VERSION_CODENAME=//p" /etc/os-release)
  step "Adding the PowerDNS apt repositories (${codename}-auth-${PDNS_AUTH_SERIES}, ${codename}-rec-${PDNS_REC_SERIES})"
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL --retry 2 --max-time 30 -o "$PDNS_KEYRING" "$PDNS_KEY_URL"
  cat >/etc/apt/sources.list.d/pdns.list <<EOF
deb [signed-by=${PDNS_KEYRING}] http://repo.powerdns.com/debian ${codename}-auth-${PDNS_AUTH_SERIES} main
deb [signed-by=${PDNS_KEYRING}] http://repo.powerdns.com/debian ${codename}-rec-${PDNS_REC_SERIES} main
EOF
  cat >/etc/apt/preferences.d/pdns <<'EOF'
Package: pdns-*
Pin: origin repo.powerdns.com
Pin-Priority: 600
EOF
}

write_auth_conf() {
  local key
  [[ -f "$PDNS_AUTH_CONF" ]] && return 0   # never overwrite the user's config
  key=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)
  cat >"$PDNS_AUTH_CONF" <<EOF
# PowerDNS Authoritative Server, written by proxmox-recipes.
# Reference: https://doc.powerdns.com/authoritative/settings.html
# After editing: systemctl restart pdns

# Zones live in SQLite (instead of the packaged bind backend, whose
# config is set aside as bind.conf.disabled).
launch=gsqlite3
gsqlite3-database=${PDNS_DB}

# Only the Recursor in this container talks to it.
local-address=127.0.0.1
local-port=5300

# HTTP API for managing zones, from private networks only.
api=yes
api-key=${key}
webserver=yes
webserver-address=0.0.0.0
webserver-port=8081
webserver-allow-from=${PRIVATE_NETS}
EOF
  chown root:pdns "$PDNS_AUTH_CONF"
  chmod 0640 "$PDNS_AUTH_CONF"

  # The package's bind.conf loads the bind backend and sets bind-* options,
  # which are unknown once only gsqlite3 is launched. Set it aside; dpkg
  # treats a removed conffile as the admin's choice and keeps it removed.
  if [[ -f /etc/powerdns/pdns.d/bind.conf ]]; then
    mv /etc/powerdns/pdns.d/bind.conf /etc/powerdns/pdns.d/bind.conf.disabled
  fi
}

create_auth_db() {
  [[ -f "$PDNS_DB" ]] && return 0
  step "Creating the zone database"
  sqlite3 "$PDNS_DB" <"$PDNS_SCHEMA"
  chown pdns:pdns "$PDNS_DB"
  chmod 0640 "$PDNS_DB"
}

write_recursor_conf() {
  [[ -f "$PDNS_REC_CONF" ]] && return 0
  cat >"$PDNS_REC_CONF" <<EOF
# PowerDNS Recursor, written by proxmox-recipes.
# Reference: https://doc.powerdns.com/recursor/yamlsettings.html
# After editing: systemctl restart pdns-recursor

incoming:
  # Answer the network on port 53, private networks only.
  listen:
    - 0.0.0.0
  allow_from: [${PRIVATE_NETS//,/, }]

recursor:
  # Names in ${PDNS_ZONE} come from the Authoritative Server in this
  # container. Add more zones the same way.
  forward_zones:
    - zone: ${PDNS_ZONE}
      forwarders:
        - 127.0.0.1:5300

dnssec:
  negative_trustanchors:
    - name: ${PDNS_ZONE}
      reason: local zone served by the Authoritative Server in this container
EOF
  chmod 0644 "$PDNS_REC_CONF"
}

create_local_zone() {
  local i ip
  for (( i = 0; i < 15; i++ )); do
    pdnsutil zone list-all >/dev/null 2>&1 && break
    sleep 1
  done
  if pdnsutil zone list-all 2>/dev/null | grep -qx "${PDNS_ZONE}\.\?"; then
    return 0
  fi
  step "Creating the ${PDNS_ZONE} zone"
  ip=$(hostname -I | awk '{ print $1 }')
  pdnsutil zone create "$PDNS_ZONE" "ns1.${PDNS_ZONE}"
  pdnsutil rrset add "$PDNS_ZONE" "ns1.${PDNS_ZONE}" A 3600 "$ip"
  pdnsutil rrset add "$PDNS_ZONE" "powerdns.${PDNS_ZONE}" A 3600 "$ip"
  # As pdnsutil says: refresh the running server's zone cache.
  pdns_control rediscover
}

check_powerdns() {
  local i status=""
  step "Testing PowerDNS"
  for (( i = 0; i < 15; i++ )); do
    status=$(dig_status "powerdns.${PDNS_ZONE}" @127.0.0.1 -p 5300 +time=2) || true
    [[ "$status" == NOERROR ]] && break
    sleep 2
  done
  [[ "$status" == NOERROR ]] || fail "The Authoritative Server does not answer for ${PDNS_ZONE} on 127.0.0.1#5300 (status: '${status}')."

  for (( i = 0; i < 15; i++ )); do
    status=$(dig_status example.com @127.0.0.1 +time=3) || true
    [[ "$status" == NOERROR ]] && break
    sleep 2
  done
  [[ "$status" == NOERROR ]] || fail "The Recursor does not answer on 127.0.0.1#53 (status: '${status}')."

  for (( i = 0; i < 15; i++ )); do
    status=$(dig_status "powerdns.${PDNS_ZONE}" @127.0.0.1 +time=3) || true
    [[ "$status" == NOERROR ]] && break
    sleep 2
  done
  [[ "$status" == NOERROR ]] || fail "The Recursor does not forward ${PDNS_ZONE} to the Authoritative Server (status: '${status}')."

  status=$(dig_status fail01.dnssec.works @127.0.0.1 +time=5) || true
  [[ "$status" == SERVFAIL ]] || fail "The Recursor is not validating DNSSEC: fail01.dnssec.works returned '${status}', expected SERVFAIL."
}
