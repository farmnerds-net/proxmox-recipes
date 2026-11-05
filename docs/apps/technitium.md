# Technitium DNS Server

[Technitium DNS Server](https://technitium.com/dns/) is a DNS server you run
and manage entirely from a web console. It can resolve names itself
(recursive), host your own zones (authoritative), block ads and malware with
block lists, and serve encrypted DNS (DNS-over-HTTPS, DNS-over-TLS,
DNS-over-QUIC).

## Install

Run on the Proxmox VE host as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/technitium.sh)"
```

The recipe runs Technitium's
[official install script](https://blog.technitium.com/2017/11/running-dns-server-on-ubuntu-linux.html)
(linked from their [README](https://github.com/TechnitiumSoftware/DnsServer#installation)).
It asks no questions. The script:

- installs Microsoft's ASP.NET Core runtime to `/opt/dotnet`
- installs the server to `/opt/technitium/dns`, with its config in `/etc/dns`
- creates a `dns-server` user and the systemd `dns` service, and starts it

## Defaults

| Setting   | Value                             |
| --------- | --------------------------------- |
| OS        | Debian 12, unprivileged container |
| CPU       | 1 core                            |
| Memory    | 1 GB (it runs on .NET)            |
| Disk      | 4 GB                              |
| Network   | DHCP on `vmbr0`                   |

## After install

The container's **Notes** in the Proxmox UI have a direct link to the web
console.

1. **Log in** at `http://<container-ip>:5380/` with user **admin**, password
   **admin**.
2. **Change the admin password right away.** Until you do, anyone on your
   network can log in with the default.
3. **Ad blocking** is set up in the web console under **Settings > Blocking**
   (add one or more block list URLs).
4. **Fixed IP:** your devices will point at this address for DNS, so it must
   not change. Either reserve it in your DHCP server, or choose a static IP
   in the recipe's Advanced mode.
5. **Use it:** set the container's IP as the DNS server in your router's DHCP
   settings (or on individual devices).

## Ports and config

| Port       | Use |
| ---------- | --- |
| 53 TCP/UDP | DNS |
| 5380       | Web console (HTTP) |
| 53443      | Web console (HTTPS, once enabled in Settings) |

Config: `/etc/dns`, managed from the web console. Logs:
`/var/log/technitium/dns` and `journalctl -u dns`.

## Updating

Inside the container:

```bash
recipe update
```

This upgrades the OS packages and then runs Technitium's install script
again, which, as their docs say, updates the server (and the .NET runtime
when needed) and restarts it. Your settings and zones are kept.

## Upstream docs

- [Install on Linux (blog)](https://blog.technitium.com/2017/11/running-dns-server-on-ubuntu-linux.html)
- [README](https://github.com/TechnitiumSoftware/DnsServer)
- [HTTP API](https://github.com/TechnitiumSoftware/DnsServer/blob/master/APIDOCS.md)
