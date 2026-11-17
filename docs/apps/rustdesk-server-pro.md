# RustDesk Server Pro

[RustDesk Server Pro](https://rustdesk.com/docs/en/self-host/rustdesk-server-pro/)
is your own server for [RustDesk](https://rustdesk.com/) remote desktop:
the ID server (`hbbs`) that lets RustDesk clients find each other, the relay
(`hbbr`) that carries a session when the two computers can't connect
directly, and a web console for users, groups, devices, address books,
access control and logs.

**It needs a paid RustDesk Server Pro licence.** The recipe installs the
server; you enter the licence in the web console afterwards.

## Install

Run on the Proxmox VE host as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/rustdesk-server-pro.sh)"
```

The recipe follows RustDesk's
[install.sh method](https://rustdesk.com/docs/en/self-host/rustdesk-server-pro/installscript/),
doing the same steps as RustDesk's own
[`install.sh`](https://github.com/rustdesk/rustdesk-server-pro/blob/main/install.sh).
It asks no questions. It:

- downloads the latest release from
  [GitHub](https://github.com/rustdesk/rustdesk-server-pro/releases)
  (the `-nativetls` build, as `install.sh` picks on systems with OpenSSL 3)
- puts `hbbs`, `hbbr` and `rustdesk-utils` in `/usr/bin` and the web
  console's files in `/var/lib/rustdesk-server/static`
- creates the `rustdesk-hbbs` and `rustdesk-hbbr` services, running as a
  `rustdesk` system user (the unprivileged-user option `install.sh` recommends)
- adds a logrotate rule for `/var/log/rustdesk-server/`, since the services
  append to their log files forever

It leaves out two steps of `install.sh`: the `ufw` firewall rules, and the
optional Nginx + Certbot setup for HTTPS. Use your own reverse proxy for
HTTPS (see below).

## Defaults

| Setting   | Value                             |
| --------- | --------------------------------- |
| OS        | Debian 13, unprivileged container |
| CPU       | 2 cores                           |
| Memory    | 1 GB                              |
| Disk      | 4 GB                              |
| Network   | DHCP on `vmbr0`                   |

Reserve the container's IP address in your router's DHCP settings (or give
it a static one in the Advanced setup): every client points at it.

## After install

The container's **Notes** in the Proxmox UI have a direct link to the web
console, the server's public key, and the ports.

### 1. Log in and change the password

Open `http://<container-ip>:21114/`. The default login is **`admin` /
`test1234`** ([RustDesk's docs](https://rustdesk.com/docs/en/self-host/rustdesk-server-pro/console/)).
Change the password straight away.

### 2. Enter your licence

The web console asks for the licence. A licence works on **one server at a
time**: it binds to the first server you enter it on. To move it to another
server, unbind the old one at
[rustdesk.com/self-host/account](https://rustdesk.com/self-host/account/)
with the email you bought it with, then enter it on the new server.
([RustDesk's licence docs](https://rustdesk.com/docs/en/self-host/rustdesk-server-pro/license/))

So don't enter it on a throwaway test container.

### 3. Set up the clients

In each RustDesk client, under **Settings > Network > ID/Relay server**:

- **ID server**: the container's IP address (or your public hostname, for
  clients outside your network)
- **Key**: the contents of `/var/lib/rustdesk-server/id_ed25519.pub`, also
  shown in the Notes and by `recipe info`'s config path

The web console can also build a custom client with these already filled in.

### 4. Email (optional)

Invites, login verification and alerts need SMTP. Add your mail server's
details in the web console's settings.

## Using it from outside your network

The web console is plain HTTP, so it can sit behind a reverse proxy or a
tunnel for HTTPS (point it at port 21114).

Remote sessions can't: RustDesk clients use their own protocol on these
ports, which must reach the container directly. Forward them on your
router:

| Port        | Protocol | Use |
| ----------- | -------- | --- |
| 21115       | TCP      | NAT type test |
| 21116       | TCP, UDP | ID server, hole punching |
| 21117       | TCP      | Relay |

The recipe never changes your router or the Proxmox host, so this is a
step for you.

## Ports and config

| Port  | Use |
| ----- | --- |
| 21114 | Web console and API (HTTP) |
| 21115 | NAT type test |
| 21116 | ID server (TCP and UDP) |
| 21117 | Relay |
| 21118, 21119 | Web client (WebSocket); only needed if you use it |

| Path | What |
| ---- | ---- |
| `/var/lib/rustdesk-server/db.sqlite3` | Database: users, devices, settings, licence |
| `/var/lib/rustdesk-server/id_ed25519`, `id_ed25519.pub` | Server key pair. Clients trust the public key, so keep the pair if you rebuild |
| `/var/lib/rustdesk-server/static/` | Web console files (replaced on update) |
| `/var/log/rustdesk-server/` | `hbbs` and `hbbr` logs |
| `/etc/systemd/system/rustdesk-hbbs.service`, `rustdesk-hbbr.service` | Services |

Back up `/var/lib/rustdesk-server/`: it holds everything that matters.

## Updating

`recipe update` inside the container upgrades the OS packages, then, if a
newer RustDesk Server Pro release is out, does what RustDesk's
[`update.sh`](https://github.com/rustdesk/rustdesk-server-pro/blob/main/update.sh)
does: stops both services, replaces the binaries and `static/`, and starts
them again. The database and key pair are kept.

## Upstream docs

- [RustDesk Server Pro](https://rustdesk.com/docs/en/self-host/rustdesk-server-pro/)
- [Install script method](https://rustdesk.com/docs/en/self-host/rustdesk-server-pro/installscript/)
- [Web console](https://rustdesk.com/docs/en/self-host/rustdesk-server-pro/console/)
- [Licence](https://rustdesk.com/docs/en/self-host/rustdesk-server-pro/license/)
