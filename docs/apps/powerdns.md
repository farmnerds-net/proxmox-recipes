# PowerDNS

[PowerDNS](https://www.powerdns.com/) makes two DNS servers, and this recipe
installs both in one container:

- **PowerDNS Recursor** answers your network on port 53. It resolves any
  name on the internet itself (recursively, with DNSSEC validation), like
  the [Unbound](unbound.md) recipe.
- **PowerDNS Authoritative Server** holds your own local zone,
  `home.arpa`, in a SQLite database. The Recursor sends every `home.arpa`
  lookup to it.

So your devices use one DNS server, and names like `nas.home.arpa` work
alongside everything on the internet. (`home.arpa` is the name
[RFC 8375](https://www.rfc-editor.org/rfc/rfc8375) reserves for home
networks.)

```
devices ──> Recursor :53 ──┬── home.arpa ──> Authoritative 127.0.0.1:5300 (SQLite)
                           └── everything else ──> the internet (DNSSEC validated)
```

## Install

Run on the Proxmox VE host as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/farmnerds-net/proxmox-recipes/main/ct/powerdns.sh)"
```

The recipe adds PowerDNS's [official apt repositories](https://repo.powerdns.com/)
for Debian 12 (Authoritative Server 5.1 and Recursor 5.4, the current stable
releases) with their signing key and pin file, then installs `pdns-server`,
`pdns-backend-sqlite3` and `pdns-recursor`. It asks no questions.

Then it:

1. Configures the Authoritative Server for SQLite on `127.0.0.1:5300`, with
   its HTTP API on port 8081 and a random API key. The package's
   `bind.conf` is set aside as `bind.conf.disabled`, since its BIND
   backend isn't used.
2. Creates the database from the package's schema.
3. Configures the Recursor to listen on port 53 and send `home.arpa` to the
   Authoritative Server.
4. Creates `home.arpa` with two names: `ns1.home.arpa` and
   `powerdns.home.arpa`, both pointing at the container.
5. Tests every part: the Authoritative Server, internet lookups, forwarding
   of `home.arpa`, and DNSSEC validation.

## Defaults

| Setting   | Value                             |
| --------- | --------------------------------- |
| OS        | Debian 12, unprivileged container |
| CPU       | 1 core                            |
| Memory    | 512 MB                            |
| Disk      | 4 GB                              |
| Network   | DHCP on `vmbr0`                   |

Both the Recursor and the API only answer private networks (`10.0.0.0/8`,
`172.16.0.0/12`, `192.168.0.0/16`).

## After install

- **Add a name** to `home.arpa` (inside the container, `pct enter <id>`):

  ```bash
  pdnsutil rrset add home.arpa nas.home.arpa A 192.168.1.50
  ```

  It works through the Recursor right away for names nobody has looked up
  yet. If you change an existing name (or one that was looked up before it
  existed), the Recursor may keep the old answer cached for up to an
  hour (the record's TTL).

- **Or use the API** from another machine. The key is in
  `/etc/powerdns/pdns.d/recipe.conf` (`grep api-key` in that file):

  ```bash
  curl -X PATCH -H "X-API-Key: <key>" \
    http://<container-ip>:8081/api/v1/servers/localhost/zones/home.arpa. \
    -d '{"rrsets":[{"name":"nas.home.arpa.","type":"A","ttl":300,"changetype":"REPLACE","records":[{"content":"192.168.1.50","disabled":false}]}]}'
  ```

  Web front-ends such as PowerDNS-Admin can use this API too. They are
  separate projects and not installed by this recipe.

- **Add another zone:** `pdnsutil zone create <zone> ns1.<zone>`, then add it
  to `forward_zones` in `/etc/powerdns/recursor.d/recipe.yml` and run
  `systemctl restart pdns-recursor`.
- **Fixed IP:** your devices will point at this address for DNS, so it must
  not change. Either reserve it in your DHCP server, or choose a static IP in
  the recipe's Advanced mode. `ns1.home.arpa` and `powerdns.home.arpa` point
  at the IP the container had at install time.
- **Use it:** set the container's IP as the DNS server in your router's DHCP
  settings (or on individual devices).

## Ports and config

| Port       | Use |
| ---------- | --- |
| 53 TCP/UDP | Recursor: DNS for your network |
| 8081       | Authoritative Server HTTP API (needs the API key) |
| 5300       | Authoritative Server, on `127.0.0.1` only |

| File | What |
| ---- | ---- |
| `/etc/powerdns/recursor.d/recipe.yml` | Recursor: listen address, allowed clients, forwarded zones |
| `/etc/powerdns/pdns.d/recipe.conf` | Authoritative Server: SQLite, address, API and API key |
| `/var/lib/powerdns/pdns.sqlite3` | Your zones and records |

## Updating

Inside the container:

```bash
recipe update
```

Both servers come from PowerDNS's apt repositories, so this upgrades them
along with the OS packages, within the same release series (Authoritative
5.1.x, Recursor 5.4.x). It then restarts both and runs the same tests as the
install. Your config and zones are never overwritten.

Moving to a newer series (e.g. Recursor 5.5) means changing the repository
line in `/etc/apt/sources.list.d/pdns.list`. Check PowerDNS's upgrade notes
first.

## Upstream docs

- [Repositories](https://repo.powerdns.com/)
- [Recursor settings](https://doc.powerdns.com/recursor/yamlsettings.html)
- [Authoritative settings](https://doc.powerdns.com/authoritative/settings.html)
- [SQLite backend](https://doc.powerdns.com/authoritative/backends/generic-sqlite3.html)
- [HTTP API](https://doc.powerdns.com/authoritative/http-api/index.html)
- [pdnsutil](https://doc.powerdns.com/authoritative/manpages/pdnsutil.1.html)
