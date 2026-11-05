# CrowdSec

[CrowdSec](https://www.crowdsec.net/) detects attacks by reading logs (for
example SSH brute-forcing or web scanners) and decides which IP addresses to
block. The blocking itself is done by **remediation components**, called
*bouncers*: small add-ons for your firewall, reverse proxy or router that ask
CrowdSec which IPs to block.

This recipe sets CrowdSec up as the **central server for your network**: its
**Local API** runs in this container, and the machines you want to protect
connect to it. A container on its own only sees its own logs and can't
firewall other machines, so on its own it protects nothing.

## Install

Run on the Proxmox VE host as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/crowdsec.sh)"
```

The recipe follows CrowdSec's
[Linux install guide](https://docs.crowdsec.net/u/getting_started/installation/linux):
it adds CrowdSec's apt repository and installs the `crowdsec` package. It
then makes the Local API listen on the network (port 8080), through
`/etc/crowdsec/config.yaml.local`.

It asks one question: **whether to share attack signals with CrowdSec.**

### Signal sharing

| | Sharing on | Sharing off (default) |
| --- | --- | --- |
| Sent to CrowdSec | For each attack detected: the attacker's IP, the scenario that caught it, a timestamp, this server's ID; plus the list of scenarios and the versions of connected components | Nothing |
| You get | The **community blocklist**: IPs that attack other CrowdSec users | Only what your own agents detect, and lists you add yourself |

With sharing off, the recipe answers "no" to the package's own question
about registering with CrowdSec's Central API, so nothing is registered,
and comments out the `online_client` section of
`/etc/crowdsec/config.yaml`, which is
[upstream's way to opt out](https://docs.crowdsec.net/u/troubleshooting/security_engine#how-to-disable-the-central-api).

With sharing on, **the community blocklist starts out empty**: the first
pull right after install receives 0 IPs, which CrowdSec's log calls
"expected if you just installed crowdsec". It checks again every 2 hours.
`cscli decisions list --origin CAPI` shows what it has received.

Either way, CrowdSec downloads its detection rules (parsers and scenarios)
from its hub, once a day, as the package does by default.

To turn sharing on later, inside the container: remove the `#` in front of
the two `online_client` lines in `/etc/crowdsec/config.yaml`, remove the
`disable_usage_metrics_export` line from `config.yaml.local`, then:

```bash
cscli capi register
systemctl restart crowdsec
```

## Defaults

| Setting   | Value                             |
| --------- | --------------------------------- |
| OS        | Debian 12, unprivileged container |
| CPU       | 1 core                            |
| Memory    | 1 GB                              |
| Disk      | 4 GB                              |
| Network   | DHCP on `vmbr0`                   |

## After install

**Fixed IP:** everything you connect points at this container's address.
Reserve it in your DHCP server, or choose a static IP in the recipe's
Advanced mode.

All commands below run inside the container (`pct enter <id>`).

### Connect a bouncer

Bouncers block the IPs CrowdSec decides on. Pick one for where you want to
block (firewall, nginx, Traefik, Caddy, OPNsense, and more) from
[CrowdSec's list](https://docs.crowdsec.net/u/bouncers/intro) and install it
on that machine. Then give it a key:

```bash
cscli bouncers add my-proxy
```

This prints an API key, shown only once. In the bouncer's config, set the
API URL to `http://<container-ip>:8080/` and the key to that value.

### Connect an agent (log processor)

To have another machine's logs analyzed, install CrowdSec on it and point it
at this server, as in CrowdSec's
[multi-server guide](https://docs.crowdsec.net/u/user_guides/multiserver_setup).
On the other machine:

```bash
cscli lapi register --url http://<container-ip>:8080
```

and turn its own Local API off with this in its
`/etc/crowdsec/config.yaml.local`:

```yaml
api:
  server:
    enable: false
```

Then, here, accept it and check:

```bash
cscli machines list
cscli machines validate <name>
```

and restart CrowdSec on the other machine.

### Useful commands

```bash
cscli decisions list            # who is blocked, and why
cscli decisions add --ip 1.2.3.4 --duration 24h   # block an IP by hand
cscli decisions delete --ip 1.2.3.4
cscli alerts list
cscli bouncers list
cscli machines list
cscli metrics
```

## Ports and config

| Port | Use |
| ---- | --- |
| 8080 | Local API, for agents and bouncers (HTTP) |
| 6060 | Prometheus metrics, on `127.0.0.1` only |

**The Local API uses plain HTTP**, so bouncer keys and agent passwords
cross your network unencrypted. Keep it on a trusted network, or set up TLS
as in CrowdSec's
[Local API configuration](https://docs.crowdsec.net/docs/local_api/configuration).

Config: `/etc/crowdsec` (`config.yaml.local` holds the recipe's settings).
Logs: `/var/log/crowdsec.log` and `journalctl -u crowdsec`.

## Updating

Inside the container:

```bash
recipe update
```

CrowdSec comes from its apt repository, so this upgrades it along with the
OS packages (keeping your config), then updates the detection rules from
the hub and restarts CrowdSec.

## Upstream docs

- [Install on Linux](https://docs.crowdsec.net/u/getting_started/installation/linux)
- [Multi-server setup](https://docs.crowdsec.net/u/user_guides/multiserver_setup)
- [Bouncers](https://docs.crowdsec.net/u/bouncers/intro)
- [Configuration reference](https://docs.crowdsec.net/docs/configuration/crowdsec_configuration)
- [Central API: what is shared](https://docs.crowdsec.net/docs/central_api/intro)
