# AdGuard Home

[AdGuard Home](https://adguard.com/adguard-home/overview.html) blocks ads
and trackers for your whole network by acting as its DNS server. It also
handles encrypted DNS (DNS-over-HTTPS, DNS-over-TLS) and per-device
settings from its web UI.

## Install

Run on the Proxmox VE host as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/adguardhome.sh)"
```

The recipe installs AdGuard Home with its
[official install script](https://github.com/AdguardTeam/AdGuardHome#automated-install-linux-unix-macos-freebsd-openbsd)
into `/opt/AdGuardHome` and runs it as a systemd service. The install asks
no questions.

## Defaults

| Setting   | Value                             |
| --------- | --------------------------------- |
| OS        | Debian 12, unprivileged container |
| CPU       | 1 core                            |
| Memory    | 512 MB                            |
| Disk      | 4 GB                              |
| Network   | DHCP on `vmbr0`                   |

## After install

The container's **Notes** in the Proxmox UI have a direct link to the setup
wizard and everything below.

1. **Run the setup wizard** at `http://<container-ip>:3000/`. It creates
   the admin account and asks which ports to use. The defaults (web UI on
   80, DNS on 53) are fine.
2. **Web UI:** after the wizard, the web UI is at `http://<container-ip>/`
   (or the port you picked). Port 3000 is no longer used.
3. **Fixed IP:** your devices will point at this address for DNS, so it
   must not change. Either reserve it in your DHCP server, or choose a
   static IP in the recipe's Advanced mode.
4. **Use it:** set the container's IP as the DNS server in your router's
   DHCP settings (or on individual devices).

The Notes are written at install time, so their link points at the
wizard on port 3000. After setup, use port 80 (or the port you chose).

## Ports and config

| Port       | Use                                |
| ---------- | ---------------------------------- |
| 53 TCP/UDP | DNS                                |
| 3000       | Setup wizard (first run only)      |
| 80         | Web UI (default, set in the wizard)|

Config: `/opt/AdGuardHome/AdGuardHome.yaml`, created by the setup wizard.

## Updating

Inside the container:

```bash
recipe update
```

This upgrades the OS packages and then runs AdGuard Home's own updater,
`/opt/AdGuardHome/AdGuardHome --update`. The **Update now** button in
AdGuard Home's web UI also works.

## Upstream docs

- [Install script (README)](https://github.com/AdguardTeam/AdGuardHome#automated-install-linux-unix-macos-freebsd-openbsd)
- [Getting started](https://adguard-dns.io/kb/adguard-home/getting-started/)
- [Configuration](https://github.com/AdguardTeam/AdGuardHome/wiki/Configuration)
