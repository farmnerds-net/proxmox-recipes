# Apache Guacamole

[Apache Guacamole](https://guacamole.apache.org/) is a clientless remote
desktop gateway. You log in to a web page and use your computers' RDP, VNC,
SSH or Telnet connections in the browser tab. Nothing is installed on the
computer you work from, or on the computers you connect to beyond the remote
access they already have (Windows Remote Desktop, macOS Screen Sharing, SSH).

Users, groups, connections, permissions and history are stored in
PostgreSQL inside the container.

## Install

Run on the Proxmox VE host as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/guacamole.sh)"
```

The recipe follows the
[Apache Guacamole manual](https://guacamole.apache.org/doc/gug/guacamole-native.html)
(v1.6.0). It asks no questions. It:

- **builds guacamole-server (guacd) from Apache's source release**, with
  Debian's libraries for RDP (FreeRDP 2), VNC, SSH, Telnet, Kubernetes,
  audio and session recording. `make install` writes the `guacd` service.
- installs **Tomcat 9 from Apache's binary release**. Guacamole 1.6.0 is a
  `javax.servlet` web app and does not run on Tomcat 10 or newer, and
  Debian 12 has no Tomcat 9 package.
- deploys Apache's **`guacamole.war`** into Tomcat
- sets up **PostgreSQL** with Guacamole's
  [database extension](https://guacamole.apache.org/doc/gug/postgresql-auth.html):
  creates `guacamole_db`, loads the schema, and creates `guacamole_user`
  with a random password
- gives the `guacadmin` account a random password in place of the
  schema's default `guacadmin`
- checks every Apache download against Apache's published SHA-256/SHA-512
  checksum

Compiling guacd takes a few minutes.

### Why Debian 12

guacamole-server 1.6.0 calls its FreeRDP 3 support experimental and
recommends FreeRDP 2. It also does not compile against Debian 13's
FreeRDP 3.15. Debian 12 ships FreeRDP 2.11 and has long-term security
support until June 2028.

### Changes from the manual's defaults

- **guacd runs as its own `guacd` user**, with a home folder in
  `/var/lib/guacd`, through a systemd drop-in
  (`/etc/systemd/system/guacd.service.d/recipe.conf`). The unit that
  `make install` writes runs guacd as `daemon`, whose home (`/usr/sbin`)
  is not writable. FreeRDP keeps its certificate store there, so RDP
  connections fail TLS negotiation without it.
- **guacd listens on `127.0.0.1:4822`**, set in `/etc/guacamole/guacd.conf`.
  By default it listens on `localhost`, which can resolve to IPv6 `::1`
  only, while the web app connects over IPv4. It is never reachable from
  outside the container.
- **Tomcat runs as a `tomcat` user** that can read, but not change, its
  own program files. Tomcat's sample web apps are not installed. The site
  root (`/`) redirects to `/guacamole/`.

## Defaults

| Setting   | Value                             |
| --------- | --------------------------------- |
| OS        | Debian 12, unprivileged container |
| CPU       | 2 cores (guacd is compiled during install and updates) |
| Memory    | 2 GB                              |
| Disk      | 8 GB                              |
| Network   | DHCP on `vmbr0`                   |

Each active session uses guacd CPU to encode the screen. For several people
connected at once, give it more cores.

## After install

The container's **Notes** in the Proxmox UI have a direct link to the web
UI, `http://<container-ip>:8080/guacamole/`.

### 1. Log in and secure the admin account

Log in as **`guacadmin`**. Guacamole's schema creates it with the
well-known password `guacadmin`, so the recipe replaces that with a random
password before the web app first starts. The install summary shows it,
and it is saved in the container:

```bash
pct exec <id> -- cat /root/guacadmin-password
```

Then create your own admin user with all permissions (**Settings >
Users**), log in as it, and delete `guacadmin`, or at least change its
password. Delete `/root/guacadmin-password` once you have.

### 2. Add connections

**Settings > Connections > New Connection**. Pick the protocol and fill in
the computer's address and, optionally, a saved login:

| To reach | Protocol | Usual port | Turn on, on that computer |
| -------- | -------- | ---------- | ------------------------- |
| Windows (Pro/Enterprise) | RDP | 3389 | Settings > System > Remote Desktop |
| macOS | VNC | 5900 | System Settings > General > Sharing > Screen Sharing |
| Linux desktop | RDP (xrdp) or VNC | 3389 / 5900 | xrdp or a VNC server |
| Linux server, Proxmox host | SSH | 22 | usually on already |

For Windows RDP, set **Security mode** to *Any* and tick **Ignore server
certificate** unless the PC has a trusted certificate.

### 3. Add family members

Create a user for each person (**Settings > Users**) and give them only
the connections they need. Users can also be put in groups.

Guacamole supports [TOTP two-factor login](https://guacamole.apache.org/doc/gug/totp-auth.html)
and single sign-on ([OpenID Connect](https://guacamole.apache.org/doc/gug/openid-auth.html),
[SAML](https://guacamole.apache.org/doc/gug/saml-auth.html)) as extensions
dropped into `/etc/guacamole/extensions/`. The recipe doesn't install them.

## Using it from outside your network

Guacamole is a normal website (HTTP and WebSocket on port 8080), so it can
go behind a reverse proxy or tunnel for HTTPS. Point the proxy at
`http://<container-ip>:8080/guacamole/`, and make sure it passes
WebSocket upgrades and doesn't buffer responses. See the manual's
[proxy guide](https://guacamole.apache.org/doc/gug/reverse-proxy.html).

Because it can open sessions on your computers, put strong passwords and
two-factor login on every account before exposing it.

## Ports and config

| Port | Use |
| ---- | --- |
| 8080 | Web UI (`/guacamole/`), HTTP and WebSocket |
| 4822 | guacd, on `127.0.0.1` only |
| 5432 | PostgreSQL, on `localhost` only |

| Path | What |
| ---- | ---- |
| `/etc/guacamole/guacamole.properties` | Web app settings and the database login (readable by `tomcat` only) |
| `/etc/guacamole/guacd.conf` | guacd settings |
| `/etc/guacamole/extensions/`, `lib/` | Database extension; PostgreSQL JDBC driver (a link to Debian's, updated by apt) |
| PostgreSQL `guacamole_db` | Users, connections, permissions, history |
| `/opt/tomcat9/current` | Tomcat 9 release in use (`CATALINA_HOME`); the previous release is kept beside it |
| `/var/lib/guacamole-tomcat/` | This Tomcat instance (`CATALINA_BASE`): `conf/`, `webapps/`, `logs/` |
| `/usr/local/sbin/guacd`, `/usr/local/lib/libguac*` | guacamole-server |
| `guacd`, `guacamole-tomcat`, `postgresql` | Services |

To back up everything that matters: `/etc/guacamole/` and a dump of the
database (`runuser -u postgres -- pg_dump guacamole_db > guacamole_db.sql`),
or simply back up the whole container.

## Updating

`recipe update` inside the container upgrades the OS packages (including
Java, PostgreSQL and the JDBC driver), then:

- **Tomcat**: if a newer 9.0 release is out, downloads it, switches
  `/opt/tomcat9/current` to it and keeps the previous one.
- **Guacamole**: if a newer release is out, rebuilds guacd from source,
  runs the database's `upgrade-pre-<version>.sql` scripts newer than the
  installed release (as the manual says), re-applies the database grants,
  and replaces the database extension and `guacamole.war`.

Your settings, users and connections are kept.

Tomcat 9.0 is supported until at least 31 March 2027, after which Apache
continues it as a 9.1 branch. A future Guacamole release built for newer
Tomcat would need a recipe change; `recipe update` will not switch Tomcat
major versions on its own.

## Upstream docs

- [Installing Guacamole natively](https://guacamole.apache.org/doc/gug/guacamole-native.html)
- [Configuring Guacamole](https://guacamole.apache.org/doc/gug/configuring-guacamole.html)
- [Database authentication (PostgreSQL)](https://guacamole.apache.org/doc/gug/postgresql-auth.html)
- [Proxying Guacamole](https://guacamole.apache.org/doc/gug/reverse-proxy.html)
- [Tomcat 9 RUNNING.txt](https://tomcat.apache.org/tomcat-9.0-doc/RUNNING.txt)
