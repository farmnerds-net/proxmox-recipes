# Pi-hole

[Pi-hole](https://pi-hole.net/) blocks ads and trackers for your whole
network by acting as its DNS server. The recipe can also install
[Unbound](https://nlnetlabs.nl/projects/unbound/about/), so Pi-hole resolves
names itself by asking the DNS root servers instead of a public resolver.

## Install

Run on the Proxmox VE host as root, **from an interactive shell**:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/pihole.sh)"
```

### Pi-hole's installer asks its own questions

Pi-hole only documents an interactive installer, so partway through the
recipe you will see Pi-hole's own screens. The defaults are fine except
for one:

- **Static IP Needed** defaults to **Exit**. Choose **Continue**. (Then give
  the container a fixed address; see below.)
- **Upstream DNS provider**: any choice. If you chose Unbound, this is
  replaced afterwards.
- The **last screen shows the web admin password**. Note it down.

The recipe will not start without a terminal, so it never gets stuck
half-built waiting for answers nobody can give.

### Unbound (optional)

The recipe asks whether to install Unbound (default: no). If you say yes,
it follows Pi-hole's [Unbound guide](https://docs.pi-hole.net/guides/dns/unbound/):

1. Checks that the container can reach the DNS root servers directly over
   UDP and TCP and is not being intercepted. If not, the install stops,
   because Unbound would not work on that network.
2. Installs Unbound with the guide's `pi-hole.conf`, listening on
   `127.0.0.1#5335`.
3. Applies the guide's Debian `resolvconf` fix.
4. Runs the guide's tests, including DNSSEC validation.
5. Makes `127.0.0.1#5335` Pi-hole's only upstream.

To answer the question in advance, set `PIHOLE_UNBOUND=yes` or
`PIHOLE_UNBOUND=no` before running the recipe.

## Defaults

| Setting   | Value                                          |
| --------- | ---------------------------------------------- |
| OS        | Debian 12, unprivileged container              |
| CPU       | 1 core                                         |
| Memory    | 512 MB (Pi-hole minimum)                       |
| Disk      | 4 GB (Pi-hole recommendation)                  |
| Network   | DHCP on `vmbr0`                                |
| Unbound   | no                                             |

## After install

- **Web UI:** `http://<container-ip>/admin`
- **Password:** shown on the installer's last screen. To change it:
  `pct exec <id> -- pihole setpassword`
- **Fixed IP:** your devices will point at this address for DNS, so it must
  not change. Either reserve it in your DHCP server, or choose a static IP in
  the recipe's Advanced mode.
- **Use it:** set the container's IP as the DNS server in your router's DHCP
  settings (or on individual devices).

## Ports and config

| Port      | Use                                   |
| --------- | ------------------------------------- |
| 53 TCP/UDP| DNS                                   |
| 80, 443   | Web UI                                |
| 5335      | Unbound, on `127.0.0.1` only (if used)|

Config: `/etc/pihole/pihole.toml` (Pi-hole),
`/etc/unbound/unbound.conf.d/pi-hole.conf` (Unbound).

## Updating

Inside the container:

```bash
recipe update
```

This upgrades the OS packages (including Unbound, if installed) and then runs
Pi-hole's own updater, `pihole -up`.

## Upstream docs

- [Installation](https://docs.pi-hole.net/main/basic-install/)
- [Unbound guide](https://docs.pi-hole.net/guides/dns/unbound/)
- [FTL configuration](https://docs.pi-hole.net/ftldns/configfile/)
- [The `pihole` command](https://docs.pi-hole.net/main/pihole-command/)
