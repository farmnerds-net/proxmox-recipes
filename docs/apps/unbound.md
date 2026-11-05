# Unbound

[Unbound](https://nlnetlabs.nl/projects/unbound/about/) is a validating,
recursive, caching DNS resolver from NLnet Labs. Instead of forwarding your
lookups to Google, Cloudflare or your ISP, it asks the DNS root servers and
then each domain's own servers directly, and checks DNSSEC signatures along
the way.

This recipe sets Unbound up as a DNS server for your local network. (If you
want Unbound behind Pi-hole instead, use the [Pi-hole](pihole.md) recipe and
say yes to its Unbound option.)

## Install

Run on the Proxmox VE host as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/unbound.sh)"
```

The recipe follows NLnet Labs'
[installation docs](https://unbound.docs.nlnetlabs.nl/en/latest/getting-started/installation.html)
and installs Debian's `unbound` package. It asks no questions.

1. Checks that the container can reach the DNS root servers directly over
   UDP and TCP and is not being intercepted. If not, the install stops,
   because a recursive resolver would not work on that network.
2. Installs Unbound and writes `/etc/unbound/unbound.conf.d/recipe.conf`,
   based on the docs'
   [local-network example](https://unbound.docs.nlnetlabs.nl/en/latest/getting-started/configuration.html).
3. Checks the config with `unbound-checkconf`, starts Unbound, and tests
   that it answers and validates DNSSEC.

## Defaults

| Setting   | Value                             |
| --------- | --------------------------------- |
| OS        | Debian 12, unprivileged container |
| CPU       | 1 core                            |
| Memory    | 512 MB                            |
| Disk      | 2 GB                              |
| Network   | DHCP on `vmbr0`                   |

What the config sets:

- **Listens** on port 53 on all interfaces.
- **Answers only private networks:** `10.0.0.0/8`, `172.16.0.0/12` and
  `192.168.0.0/16` (and the container itself). Anything else is refused.
- **DNSSEC validation:** on (Debian's package enables it).
- **Hides** the server's name and version, **prefetches** popular names, and
  stops public names from resolving to private addresses (DNS rebinding
  protection).
- **IPv6** lookups are turned off if the container has no IPv6 route.

## After install

- **Settings:** there is no web UI. Run `pct enter <id>`, edit
  `/etc/unbound/unbound.conf.d/recipe.conf`, run `unbound-checkconf`, then
  `systemctl restart unbound`. See the
  [unbound.conf reference](https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html).
- **Fixed IP:** your devices will point at this address for DNS, so it must
  not change. Either reserve it in your DHCP server, or choose a static IP in
  the recipe's Advanced mode.
- **Use it:** set the container's IP as the DNS server in your router's DHCP
  settings (or on individual devices), or as the upstream of another DNS
  server such as AdGuard Home or Blocky.
- **First lookups are slower:** a fresh resolver has an empty cache, so the
  first lookup of each name takes longer. It speeds up as the cache fills.

## Ports and config

| Port       | Use |
| ---------- | --- |
| 53 TCP/UDP | DNS |

Config: `/etc/unbound/unbound.conf.d/recipe.conf` (the recipe's settings).
Debian's own files in the same folder (DNSSEC trust anchor, remote control)
are left as they are.

## Updating

Inside the container:

```bash
recipe update
```

Unbound comes from Debian, so this upgrades it along with the OS packages.
It then re-checks the config, restarts Unbound and runs the same tests as
the install. Your config is never overwritten.

## Upstream docs

- [Installation](https://unbound.docs.nlnetlabs.nl/en/latest/getting-started/installation.html)
- [Configuration](https://unbound.docs.nlnetlabs.nl/en/latest/getting-started/configuration.html)
- [unbound.conf reference](https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html)
