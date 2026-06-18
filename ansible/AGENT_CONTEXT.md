# Agent Context — KardiAI Ansible Repo

Quick orientation guide for an AI agent working in this repository. Covers key design decisions, patterns, and gotchas that are not directly readable from the code.

---

## Infrastructure overview

Four managed hosts in two groups:

```
kardi_monitoring:
  de.mon.kardi-ai.org        Frankfurt, user=jarekmacku
  sg.mon.kardi-ai.org        Singapore, user=jarekmacku

kardi_proxy:
  proxy.sg.prod.kardi-ai.org  Singapore, IP=52.74.117.163, user=admin
  proxy.sg.test.kardi-ai.org  Singapore, IP=18.136.169.176, user=admin
```

Proxy servers **have no public DNS records for their hostname** — wherever they need to be addressed (Prometheus scrape, UFW rules), their IP addresses are used directly.

---

## Role execution order in playbooks

### kardi-monitoring.yml
```
base → firewall → docker → node_exporter → blackbox_exporter →
prometheus → alertmanager → grafana → nginx → certbot-route53 → nginx-config
```
`certbot-route53` runs after `nginx` (nginx must be installed) but before `nginx-config` (nginx-config requires certificates to already exist on disk).

### kardi-proxy.yml
```
base → firewall → docker → node_exporter → certbot-route53 → nginx → nginx-config
```

---

## Variable patterns

### group_vars → host_vars cascade
Variables in `group_vars` serve as defaults. Host-specific overrides live in `host_vars`. Key example: certbot domains.

- `group_vars/kardi_monitoring/certbot.yml` → `certbot_domains: ["{{ inventory_hostname }}"]`
- `host_vars/de.mon.kardi-ai.org/certbot.yml` → adds `uptime.{{ inventory_hostname }}` and `status.kardi-ai.com`
- `host_vars/sg.mon.kardi-ai.org/certbot.yml` → adds only `{{ inventory_hostname }}` (same as group default, explicit override)

### Plain config vs. encrypted secrets
Unencrypted files: `certbot.yml`, `nginx.yml`, `prometheus.yml`, `base.yaml`, `nginx-proxy.yml`  
Ansible-vault encrypted: `*-secrets.yml`, `aws-vault.yml` (filenames containing "vault" or "secrets")

---

## Prometheus — per-host scraping (node_exporter)

**Why file_sd instead of static_configs:**  
The two monitoring servers need to scrape different sets of targets (SG scrapes proxy servers, DE does not). The Prometheus config is shared (`group_files/kardi_monitoring/prometheus.yml`). Solution: `file_sd_configs` pointing at `node_exporter_targets.yml` — each monitoring server has its own target file under `host_files/<hostname>/`.

```
host_files/sg.mon.kardi-ai.org/node_exporter_targets.yml  ← localhost + proxy prod + proxy test
host_files/de.mon.kardi-ai.org/node_exporter_targets.yml  ← localhost only
```

The path to the target file is set in `group_vars/kardi_monitoring/prometheus.yml`:
```yaml
node_exporter_targets_file: "{{ playbook_dir }}/../inventory/host_files/{{ inventory_hostname }}/node_exporter_targets.yml"
```

The `prometheus` role copies this file to the server (mirrors the existing `web-targets.yml` copy task for blackbox).

---

## Alert label conventions

| environment value | What it monitors | Alertmanager channel |
|---|---|---|
| `Production EU` / `Production UAE` | Application endpoints (EU/UAE k8s) | slack-production |
| `Website` | Public website | slack-production |
| `Infrastructure` | Monitoring servers (de.mon, sg.mon) | slack-production |
| `Infra Prod` | proxy.sg.prod.kardi-ai.org | slack-production |
| `Infra Test` | proxy.sg.test.kardi-ai.org | slack-test |
| `Test EU` / `Test UAE` | Test environment endpoints | slack-test |
| `Training EU` | Training environment | slack-training |

`reporter` label = "Singapore" or "Germany" — identifies which monitoring server generated the alert (important because both run Alertmanager independently).

---

## TLS certificates — why certbot-route53

Monitoring servers previously used `certbot-nginx` (HTTP-01 challenge). Problem: nginx needs a cert to start, certbot-nginx needs nginx to issue a cert — chicken-and-egg. Additionally, the `certbot` version from Debian apt is too old to support the `rename` subcommand, which causes issues with `-0001` suffixes on re-issuance.

**Solution:** `certbot-route53` (DNS-01 challenge) — independent of nginx, works even when nginx is not running. Requires AWS credentials for Route53.

AWS credentials are stored in:
```
inventory/group_vars/kardi_monitoring/aws-vault.yml   ← ansible-vault encrypted
inventory/group_vars/kardi_proxy/aws-valut.yaml       ← note: typo "valut" instead of "vault"!
```

---

## UFW firewall — hostname lookup

`community.general.ufw` **does not accept hostnames** in `from_ip`, only IPs. The firewall role resolves hostnames to IPs using:

```jinja2
{{ lookup('pipe', 'getent hosts ' ~ item.1).split() | first }}
```

This lookup runs on the **control node** (the machine running Ansible), not on the target server. The hostname `sg.mon.kardi-ai.org` must be resolvable from the control node.

The `expose_tcp_ports_restricted` variable in `host_vars/<host>/base.yaml`:
```yaml
expose_tcp_ports_restricted:
  - port: 9100
    from_ips:
      - "sg.mon.kardi-ai.org"    # or a direct IP — regex detects it and skips the lookup
```

---

## Certbot — known gotcha: -0001 suffix

If certbot finds that the live directory `/etc/letsencrypt/live/<domain>/` already exists (from a previous failed issuance), it creates the cert with a `-0001` suffix. Renewal then fails because it looks for `<domain>-0001` instead of `<domain>`.

The `certbot-nginx` role contains cleanup logic — it detects suffixed certs, deletes both the broken base cert and the suffixed cert, then re-issues cleanly. The `certbot-route53` role is less prone to this problem since it operates independently of nginx.

If manual cleanup is needed:
```bash
certbot delete --cert-name sg.mon.kardi-ai.org --non-interactive
certbot delete --cert-name sg.mon.kardi-ai.org-0001 --non-interactive
rm -rf /etc/letsencrypt/live/sg.mon.kardi-ai.org   # if the directory persists
```

---

## Key files for orientation

| File | Contains |
|---|---|
| `inventory/hosts.ini` | All hosts and their ansible_user |
| `inventory/group_vars/kardi_monitoring/prometheus.yml` | Versions, paths to target files |
| `inventory/group_vars/kardi_proxy/certbot.yml` | `kardiai_proxy_hosts` list + upstream LB DNS |
| `inventory/group_files/kardi_monitoring/prometheus.yml` | Prometheus scrape config (shared) |
| `inventory/group_files/kardi_monitoring/alertmanager_alert_rules.yaml` | All alert rules |
| `roles/alertmanager/templates/alertmanager.yml.j2` | Routing + Slack receivers |
| `roles/firewall/tasks/main.yml` | UFW rules with hostname→IP lookup |
| `roles/certbot-route53/tasks/main.yml` | DNS-01 cert issuance (domain discovery or explicit list) |

---

## Typos and quirks in the repository

- `aws-valut.yaml` (not `aws-vault.yaml`) — typo in vault filenames for both kardi_proxy and kardi_monitoring. **Do not rename without updating all references.**
- `vault-setup.sh` references `valut-env.sh` (typo). Both files exist.
- Proxy `host_vars` file `nginx-proxy.yml` duplicates the `kardiai_proxy_hosts` definition — once in group_vars, once in host_vars for prod. Certbot uses the group_vars value.
