# cloudflared

[cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
is the connector for **Cloudflare Tunnel**. It lets you reach apps on your
network (say, a web UI in another container) through a hostname on your
Cloudflare domain, without opening any ports on your router. cloudflared
makes outbound connections to Cloudflare, and Cloudflare sends visitors
down them.

## Install

Run on the Proxmox VE host as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/cloudflared.sh)"
```

The recipe adds Cloudflare's [official apt repository](https://pkg.cloudflare.com/index.html)
for Debian 12 and installs the `cloudflared` package. It asks no questions.

### Why it doesn't ask for your tunnel token

Connecting cloudflared needs a **tunnel token** from the Cloudflare
dashboard. The token is a secret: anyone who has it can run your tunnel. The
recipe passes its options into the container on a command line, which other
users of the Proxmox host can see, so it doesn't take the token at all. You
paste it in inside the container instead (below). It never goes through the
recipe, its logs, or the host.

## Connect the tunnel

You need a domain on Cloudflare first.

1. In the Cloudflare dashboard, go to **Networking > Tunnels** and select
   **Create a tunnel**. Choose **Cloudflared**, give it a name, and save.
2. Choose **Debian** as the operating system. The dashboard shows an install
   command. It ends with a line like:

   ```
   sudo cloudflared service install eyJhIjoi...
   ```

3. On the Proxmox host, run `pct enter <id>`, then run **only that last
   line, without `sudo`** (the container has no `sudo`, and you are already
   root). cloudflared is already installed, so skip the other lines:

   ```bash
   cloudflared service install eyJhIjoi...
   ```

   This saves the token, creates the `cloudflared` service and starts it.

4. Back in the dashboard, the tunnel should show as **Healthy**. Select
   **Continue** to add routes.

## Add routes

In the dashboard, open the tunnel, go to **Routes**, and choose
**Add route > Published application**. Pick a subdomain and domain, and
enter the app's address as the **service URL**.

**Use LAN addresses, not `localhost`.** Your apps run in other containers,
so `localhost` here means the cloudflared container itself. For example:

| App | Service URL |
| --- | ----------- |
| AdGuard Home web UI | `http://192.168.1.21:80` |
| Technitium web console | `http://192.168.1.22:5380` |

Anyone on the internet can reach a published application. To limit who can
log in, put a Cloudflare Access application in front of it (see Cloudflare's
docs).

## Defaults

| Setting   | Value                             |
| --------- | --------------------------------- |
| OS        | Debian 12, unprivileged container |
| CPU       | 1 core                            |
| Memory    | 512 MB                            |
| Disk      | 2 GB                              |
| Network   | DHCP on `vmbr0`                   |

## Ports and config

No inbound ports. cloudflared only makes outbound connections to Cloudflare
(port 7844).

The tunnel's routes and settings live in the Cloudflare dashboard. Inside the
container: `systemctl status cloudflared`, logs with `journalctl -u cloudflared`.

**Ping (ICMP) through the tunnel** is off by default. cloudflared logs a
warning about `ping_group_range` at start. This only matters if you use the
tunnel for private-network access and want to ping hosts through it; web apps
are unaffected.

## Updating

Inside the container:

```bash
recipe update
```

cloudflared comes from Cloudflare's apt repository, so this upgrades it along
with the OS packages and then restarts the tunnel, if one is connected.

## Upstream docs

- [Cloudflare package repository](https://pkg.cloudflare.com/index.html)
- [Create a tunnel (dashboard)](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/create-remote-tunnel/)
- [Cloudflare Tunnel overview](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
