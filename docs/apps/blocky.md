# Blocky

[Blocky](https://0xerr0r.github.io/blocky/) is a fast, lightweight DNS proxy
and ad blocker. It is configured with a single YAML file and has no
built-in web UI.

## Install

Run on the Proxmox VE host as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/blocky.sh)"
```

The recipe follows Blocky's
[installation docs](https://0xerr0r.github.io/blocky/latest/installation/):
it downloads the official release binary for your architecture from
[GitHub](https://github.com/0xERR0R/blocky/releases), checks it against the
release's published checksums, and installs it to `/usr/local/bin/blocky`.
It asks no questions.

Blocky runs as a systemd service under its own `blocky` user, not root (the
docs advise against root). The service grants it the one permission it needs
to use port 53 (`CAP_NET_BIND_SERVICE`, as the docs describe).

## Defaults

| Setting   | Value                             |
| --------- | --------------------------------- |
| OS        | Debian 12, unprivileged container |
| CPU       | 1 core                            |
| Memory    | 512 MB                            |
| Disk      | 2 GB                              |
| Network   | DHCP on `vmbr0`                   |

The starter config, `/etc/blocky/config.yml`:

- **Upstream DNS:** Cloudflare (`1.1.1.1`) and Quad9 (`9.9.9.9`)
- **Blocklist:** [StevenBlack hosts](https://github.com/StevenBlack/hosts),
  the list used in Blocky's own examples
- **Ports:** DNS on 53, HTTP API on 4000

## After install

- **Settings:** there is no web UI. Run `pct enter <id>`, edit
  `/etc/blocky/config.yml` (see the
  [configuration reference](https://0xerr0r.github.io/blocky/latest/configuration/)),
  then `systemctl restart blocky`.
- **Fixed IP:** your devices will point at this address for DNS, so it must
  not change. Either reserve it in your DHCP server, or choose a static IP in
  the recipe's Advanced mode.
- **Use it:** set the container's IP as the DNS server in your router's DHCP
  settings (or on individual devices).
- **Web UI (optional):** Blocky's docs list community web UIs (Blocky
  Frontend, BlockyUI, Blocky Visor) that talk to its API on port 4000. They
  are separate projects and not installed by this recipe.

## Ports and config

| Port       | Use                                       |
| ---------- | ----------------------------------------- |
| 53 TCP/UDP | DNS                                       |
| 4000       | REST API, Prometheus metrics, DNS-over-HTTPS |

Config: `/etc/blocky/config.yml`. Service: `blocky.service`; logs with
`journalctl -u blocky`.

## Updating

Inside the container:

```bash
recipe update
```

This upgrades the OS packages, then checks GitHub for a newer Blocky
release. If there is one, it downloads it, verifies its checksum, replaces
the binary and restarts the service. Your config is never touched.

## Upstream docs

- [Installation](https://0xerr0r.github.io/blocky/latest/installation/)
- [Configuration](https://0xerr0r.github.io/blocky/latest/configuration/)
- [Releases](https://github.com/0xERR0R/blocky/releases)
