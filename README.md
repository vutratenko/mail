# mail — GitOps manifests for docker-mailserver on sion2k.ru

Kubernetes deployment of [docker-mailserver](https://github.com/docker-mailserver/docker-mailserver) for domain **sion2k.ru**, managed via Argo CD in namespace `shturval-cd`.

## Layout

| Path | Purpose |
|------|---------|
| `values.yaml` | Helm values for official `docker-mailserver` chart |
| `deploy/` | cert-manager Certificate for `mail.sion2k.ru` |
| `argocd/` | Argo CD Application (multi-source: Helm + values + deploy) |
| `ops/` | Apply Argo CD app and bootstrap mailbox/DKIM |

## Architecture

- **FQDN:** `mail.sion2k.ru`
- **Mailbox:** `vladimir@sion2k.ru`
- **Alias:** `postmaster@sion2k.ru` → `vladimir@sion2k.ru`
- **LoadBalancer VIP:** `192.168.88.111` (kube-vip; `.25` is occupied on LAN)
- **Public IP:** `95.165.3.62` — port-specific DNAT on router
- **TLS:** cert-manager `corp-acme` (HTTP-01 via nginx ingress)
- **Storage:** `proxmox-data-xfs`

Mail ports (25, 465, 587, 993) hit the mail VIP. HTTP/HTTPS for ACME (`mail.sion2k.ru:80/443`) must reach ingress `192.168.88.9`, not the mail pod.

## Prerequisites

- Cluster: `sion2k-cluster` with cert-manager, kube-vip, nginx ingress
- DNS A record: `mail.sion2k.ru` → `95.165.3.62`
- Router DNAT (see below)

## Quick start

1. Push this repo to GitHub (or ensure `main` is up to date).

2. Apply Argo CD Application:

```bash
./ops/apply-argocd.sh
```

3. Wait for sync, TLS certificate, and LoadBalancer:

```bash
kubectl -n shturval-cd get application mail
kubectl -n mail get certificate,pods,svc
kubectl -n mail get svc docker-mailserver -o wide
```

4. Bootstrap mailbox (password **not** stored in git):

```bash
chmod +x ops/*.sh
./ops/bootstrap-mailbox.sh 'your-strong-password'
```

## Router DNAT (manual)

Forward from public IP `95.165.3.62`:

| Ports | Target | Purpose |
|-------|--------|---------|
| TCP 25, 465, 587, 993 | `192.168.88.111` | SMTP / submission / IMAPS |
| TCP 80, 443 | `192.168.88.9` | ACME HTTP-01 for `mail.sion2k.ru` |

Example MikroTik:

```
/ip firewall nat
add chain=dstnat protocol=tcp dst-address=95.165.3.62 dst-port=25,465,587,993 \
  action=dst-nat to-addresses=192.168.88.111
```

Ensure 80/443 for the same public IP already reach ingress (same as other `*.sion2k.ru` services).

## DNS (nic.ru)

Fix and complete after deploy:

| Type | Name | Value |
|------|------|-------|
| MX | `sion2k.ru` | `10 mail.sion2k.ru.` (**not** bare IP) |
| A | `mail.sion2k.ru` | `95.165.3.62` |
| TXT | `sion2k.ru` | `v=spf1 mx ~all` |
| TXT | `mail._domainkey.sion2k.ru` | from `./ops/bootstrap-mailbox.sh` output |
| TXT | `_dmarc.sion2k.ru` | `v=DMARC1; p=none; rua=mailto:vladimir@sion2k.ru` |
| PTR | `95.165.3.62` | `mail.sion2k.ru` (request from ISP) |

**Current issue:** MX points to `95.165.3.62` instead of `mail.sion2k.ru` — fix before relying on inbound mail.

## Client settings

| Setting | Value |
|---------|-------|
| IMAP | `mail.sion2k.ru`, port 993, SSL/TLS |
| SMTP | `mail.sion2k.ru`, port 587, STARTTLS |
| SMTP (SSL) | port 465 |
| Username | full address `vladimir@sion2k.ru` |

## Verify

```bash
dig +short MX sion2k.ru
dig +short A mail.sion2k.ru
openssl s_client -connect mail.sion2k.ru:993 -servername mail.sion2k.ru </dev/null
kubectl -n mail logs deploy/docker-mailserver --tail=50
```

Send a test message via [mail-tester.com](https://www.mail-tester.com/) after SPF/DKIM/DMARC/PTR are set.

## Notes

- **Port 25:** Beeline may block outbound/inbound SMTP on residential lines; if mail fails, check ISP policy first.
- **proxyProtocol:** disabled — kube-vip is not HAProxy.
- **ClamAV / Fail2ban:** disabled to reduce resource use in Kubernetes.
- **Rspamd:** enabled (DKIM signing via Rspamd, not OpenDKIM).

## Chart reference

- Helm repo: `https://docker-mailserver.github.io/docker-mailserver-helm`
- Chart: `docker-mailserver` **5.1.1**
- Image: `ghcr.io/docker-mailserver/docker-mailserver:15.1.0`
