# shellcheck shell=bash
#
# install/crowdsec.sh - CrowdSec Security Engine, set up as the central
# Local API (LAPI) for a network: agents and remediation components
# (bouncers) on other machines report to it and fetch decisions from it.
#
# Runs inside the container, sourced by misc/install.func. Follows
# CrowdSec's official documentation:
#
#   Install:  https://docs.crowdsec.net/u/getting_started/installation/linux
#             (manual repository setup for Debian: debian-archive-keyring,
#             the packagecloud.io/crowdsec/crowdsec GPG key in
#             /etc/apt/keyrings, the 'any any main' repository, then
#             'apt install crowdsec')
#   Central API, opting out:
#             https://docs.crowdsec.net/u/troubleshooting/security_engine#how-to-disable-the-central-api
#             ("comment out the online_client section of the
#             configuration file")
#   Config:   https://docs.crowdsec.net/docs/configuration/crowdsec_configuration
#             (config.yaml.local overrides config.yaml;
#             api.server.listen_uri; api.server.disable_usage_metrics_export)
#
# The package asks two debconf questions: whether to run a Local API
# (crowdsec/lapi) and whether to register with the Central API
# (crowdsec/capi, default yes, which runs 'cscli capi register' during the
# install). The recipe answers them beforehand: Local API yes, Central API
# from CROWDSEC_SHARING. With sharing off, nothing is registered, and the
# online_client section is commented out as upstream's docs describe, so
# the engine never talks to the Central API. It still downloads detection
# rules from CrowdSec's hub (hub-cdn.crowdsec.net), daily, as packaged.
#
# App options (from ct/crowdsec.sh):
#   CROWDSEC_SHARING   yes | no (default no)

# shellcheck disable=SC2034  # read by misc/install.func
{
  APP_PORTS="8080/tcp (Local API, for agents and bouncers), 6060 on 127.0.0.1 only (Prometheus metrics)"
  APP_CONFIG="/etc/crowdsec/config.yaml.local (recipe settings), /etc/crowdsec (all config); manage with cscli"
}

CS_KEYRING="/etc/apt/keyrings/crowdsec_crowdsec-archive-keyring.gpg"
CS_KEY_URL="https://packagecloud.io/crowdsec/crowdsec/gpgkey"
CS_LIST="/etc/apt/sources.list.d/crowdsec_crowdsec.list"
CS_CONF="/etc/crowdsec/config.yaml"
CS_CONF_LOCAL="/etc/crowdsec/config.yaml.local"
CS_PORT=8080

app_install() {
  local sharing=${CROWDSEC_SHARING:-no}
  [[ "$sharing" == yes || "$sharing" == no ]] || fail "CROWDSEC_SHARING must be 'yes' or 'no'."

  step "Adding CrowdSec's apt repository"
  apt_quiet install --no-install-recommends debian-archive-keyring gnupg
  mkdir -p /etc/apt/keyrings
  curl -fsSL --retry 2 --max-time 30 "$CS_KEY_URL" | gpg --dearmor --yes -o "$CS_KEYRING"
  printf 'deb [signed-by=%s] https://packagecloud.io/crowdsec/crowdsec/any any main\n' \
    "$CS_KEYRING" >"$CS_LIST"
  apt_quiet update

  step "Answering the package's setup questions (Central API: ${sharing})"
  if [[ "$sharing" == yes ]]; then
    printf 'crowdsec crowdsec/lapi boolean true\ncrowdsec crowdsec/capi boolean true\n' | debconf-set-selections
  else
    printf 'crowdsec crowdsec/lapi boolean true\ncrowdsec crowdsec/capi boolean false\n' | debconf-set-selections
  fi

  step "Installing CrowdSec"
  apt_quiet install crowdsec

  write_local_conf "$sharing"
  if [[ "$sharing" == no ]]; then
    disable_central_api
  fi
  systemctl restart crowdsec
  check_crowdsec
}

# CrowdSec comes from its apt repository, so 'recipe update' has already
# upgraded the package with the OS packages (keeping the recipe's edits to
# config.yaml). Refresh the hub's detection rules and restart.
app_update() {
  step "Updating detection rules from the CrowdSec hub"
  cscli hub update
  cscli hub upgrade
  systemctl restart crowdsec
  check_crowdsec
}

app_version() {
  dpkg-query -W -f '${Version}' crowdsec 2>/dev/null
}

# Overrides kept apart from the packaged config.yaml, as upstream allows.
write_local_conf() {   # <sharing yes|no>
  step "Making the Local API reachable on the network (port ${CS_PORT})"
  {
    printf '# Written by proxmox-recipes. Overrides %s.\n' "$CS_CONF"
    printf '# Docs: https://docs.crowdsec.net/docs/configuration/crowdsec_configuration\n'
    printf 'api:\n  server:\n    listen_uri: 0.0.0.0:%s\n' "$CS_PORT"
    if [[ "$1" == no ]]; then
      printf '    disable_usage_metrics_export: true\n'
    fi
  } >"$CS_CONF_LOCAL"
}

# Upstream's way to opt out: comment out the online_client section.
disable_central_api() {
  step "Turning off the Central API (no signal sharing)"
  sed -i \
    -e 's|^\(    online_client:\)|#\1|' \
    -e 's|^\(      credentials_path: /etc/crowdsec/online_api_credentials.yaml\)|#\1|' \
    "$CS_CONF"
  if grep -q '^    online_client:' "$CS_CONF"; then
    fail "Could not turn off the Central API in ${CS_CONF}; its layout has changed."
  fi
}

check_crowdsec() {
  local i
  step "Waiting for CrowdSec to start"
  for (( i = 0; i < 30; i++ )); do
    if systemctl is-active --quiet crowdsec && cscli lapi status >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  journalctl -u crowdsec -n 20 --no-pager >&2 || true
  fail "CrowdSec did not start (its Local API does not answer)."
}
