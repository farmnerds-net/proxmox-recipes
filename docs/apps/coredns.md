# CoreDNS

[CoreDNS](https://coredns.io/) is a fast, flexible DNS server built from
plugins. It is configured with one file, the `Corefile`, and can forward,
cache, serve your own zones, rewrite names and much more. It has no web UI.

## Install

Run on the Proxmox VE host as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/coredns.sh)"
```

The recipe follows CoreDNS's
[installation docs](https://coredns.io/manual/toc/#installation): it
downloads the official pre-compiled release for your architecture from
[GitHub](https://github.com/coredns/coredns/releases) and checks it against
the release's published checksum. It asks no questions.

It then installs the CoreDNS project's own
[systemd files](https://github.com/coredns/deployment/tree/master/systemd)
where their README says to put them:

| File | Goes to | What it does |
| ---- | ------- | ------------ |
| `coredns` binary | `/usr/bin/coredns` | the server |
| `coredns.service` | `/etc/systemd/system/` | runs CoreDNS as the `coredns` user, with only the permission to use port 53 |
| `coredns-sysusers.conf` | `/usr/lib/sysusers.d/` | creates the `coredns` user |
| `coredns-tmpfiles.conf` | `/usr/lib/tmpfiles.d/` | creates `/var/lib/coredns` |
| `coredns-log.conf` | `/etc/logrotate.d/coredns` | rotates the logs |

## Defaults

| Setting   | Value                             |
| --------- | --------------------------------- |
| OS        | Debian 12, unprivileged container |
| CPU       | 1 core                            |
| Memory    | 512 MB                            |
| Disk      | 2 GB                              |
| Network   | DHCP on `vmbr0`                   |

The starter `/etc/coredns/Corefile` follows the docs' forward-and-cache
example:

```
.:53 {
    forward . 1.1.1.1 9.9.9.9
    cache
    errors
}
```

It forwards every query to Cloudflare and Quad9 and caches the answers.
Per-query logging (`log`) is there but commented out.

## After install

- **Settings:** there is no web UI. Run `pct enter <id>`, edit
  `/etc/coredns/Corefile`, then `systemctl restart coredns`. See the
  [manual](https://coredns.io/manual/toc/) and the
  [plugin list](https://coredns.io/plugins/).
- **Use your own resolver:** if you also run the [Unbound](unbound.md)
  recipe, replace `1.1.1.1 9.9.9.9` with the Unbound container's IP.
- **Fixed IP:** your devices will point at this address for DNS, so it must
  not change. Either reserve it in your DHCP server, or choose a static IP in
  the recipe's Advanced mode.
- **Use it:** set the container's IP as the DNS server in your router's DHCP
  settings (or on individual devices).

## Ports and config

| Port       | Use |
| ---------- | --- |
| 53 TCP/UDP | DNS |

Config: `/etc/coredns/Corefile`. Logs: `/var/log/coredns.log` and
`/var/log/coredns.err.log` (rotated by logrotate).

## Updating

Inside the container:

```bash
recipe update
```

This upgrades the OS packages, then checks GitHub for a newer CoreDNS
release. If there is one, it downloads it, verifies its checksum, replaces
the binary, restarts the service and tests that it answers. Your Corefile is
never touched.

## Upstream docs

- [Manual](https://coredns.io/manual/toc/)
- [Plugins](https://coredns.io/plugins/)
- [Releases](https://github.com/coredns/coredns/releases)
- [systemd deployment files](https://github.com/coredns/deployment/tree/master/systemd)
