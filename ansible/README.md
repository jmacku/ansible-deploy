# KardiAI Infrastructure — Ansible

Ansible playbooks for managing KardiAI infrastructure: monitoring servers (DE, SG) and proxy servers (SG prod/test).

---

## Infrastructure

| Host | Group | Region | Role |
|---|---|---|---|
| `de.mon.kardi-ai.org` | `kardi_monitoring` | Frankfurt | Prometheus, Alertmanager, Grafana, Nginx |
| `sg.mon.kardi-ai.org` | `kardi_monitoring` | Singapore | Prometheus, Alertmanager, Grafana, Nginx |
| `proxy.sg.prod.kardi-ai.org` | `kardi_proxy` | Singapore | Nginx reverse proxy (prod) |
| `proxy.sg.test.kardi-ai.org` | `kardi_proxy` | Singapore | Nginx reverse proxy (test) |

**Note:** Proxy servers have internal-only hostnames (no public DNS) — their IP addresses are used in configuration wherever they need to be addressed.

---

## Prerequisites

### Python dependencies
```bash
pip install -r requirements.txt
ansible-galaxy install -r requirements-galaxy.txt
```

### Vault password

All secrets are encrypted with `ansible-vault`. Set the password before running any playbook:

```bash
source vault-setup.sh
# enter the vault password when prompted

# Verify:
env | grep ANSIBLE
```

### AWS credentials (monitoring servers — Let's Encrypt DNS-01)

Monitoring servers use `certbot-route53` to issue TLS certificates via Route53 DNS-01 challenge. AWS credentials must be in:

```
inventory/group_vars/kardi_monitoring/aws-vault.yaml   ← must be vault-encrypted!
```

```bash
# Fill in credentials, then encrypt:
ansible-vault encrypt inventory/group_vars/kardi_monitoring/aws-vault.yaml
```

---

## Running playbooks

```bash
# Monitoring servers
ansible-playbook playbooks/kardi-monitoring.yml

# Proxy servers
ansible-playbook playbooks/kardi-proxy.yml

# Uptime Kuma
ansible-playbook playbooks/uptime-kuma.yml

# Limit to a specific host
ansible-playbook playbooks/kardi-proxy.yml -l proxy.sg.test.kardi-ai.org

# Start from a specific task
ansible-playbook playbooks/kardi-monitoring.yml --start-at-task="Copy Prometheus config"
```

---

## Alertmanager — environment labels

Alert routing in Alertmanager is driven by the `environment` label. Slack channels:

| environment value | Slack channel |
|---|---|
| `Production EU`, `Production UAE`, `Website` | `#slack-production` |
| `Infra Prod`, `Infrastructure` | `#slack-production` |
| `Test EU`, `Test UAE`, `Infra Test` | `#slack-test` |
| `Training EU` | `#slack-training` |

`Infra Prod` / `Infra Test` labels are used by proxy servers (scraped via SG monitoring). `Infrastructure` is used by the monitoring servers themselves. The `reporter` label (Singapore / Germany) identifies which monitoring server sent the alert.

---

## Monitoring — what is scraped from where

- **SG monitoring** scrapes: itself + proxy prod + proxy test (all in Singapore)
- **DE monitoring** scrapes: itself only (proxy servers are too far away)

node_exporter target files are per-host at `inventory/host_files/<hostname>/node_exporter_targets.yml`.

---

## TLS certificates

| Server | Method | Notes |
|---|---|---|
| Monitoring servers | `certbot-route53` (DNS-01) | Independent of Nginx, uses AWS Route53 |
| Proxy servers | `certbot-route53` (DNS-01) | Same method |

Monitoring servers have per-host domain overrides in `host_vars`:
- `de.mon`: `de.mon.kardi-ai.org`, `uptime.de.mon.kardi-ai.org`, `status.kardi-ai.com`
- `sg.mon`: `sg.mon.kardi-ai.org` only

---

## Firewall

The `firewall` role uses UFW. Key variables in `host_vars/<host>/base.yaml`:

```yaml
expose_tcp_ports:           # publicly open ports
  - 80
  - 443

expose_tcp_ports_restricted:  # ports restricted to specific sources
  - port: 9100
    from_ips:
      - "sg.mon.kardi-ai.org"   # hostname → resolved via getent on control node
```

UFW does not accept hostnames — the role automatically resolves them to IPs using `getent hosts` on the control node (the machine running Ansible).

> Note: port 9100 has to be opened in AWS SecurityGroup as well

---

## Repository structure

```
ansible/
├── ansible.cfg                     # global configuration
├── inventory/
│   ├── hosts.ini                   # host inventory
│   ├── group_vars/
│   │   ├── kardi_monitoring/       # shared vars for monitoring group
│   │   └── kardi_proxy/            # shared vars for proxy group (incl. base.yaml, aws-vault.yaml)
│   ├── host_vars/
│   │   ├── de.mon.kardi-ai.org/    # certbot.yml (extra domains), base.yaml
│   │   ├── sg.mon.kardi-ai.org/    # base.yaml
│   │   ├── proxy.sg.prod.kardi-ai.org/  # nginx-proxy.yml (prod domains + upstream)
│   │   └── proxy.sg.test.kardi-ai.org/  # nginx-proxy.yml (test domains + upstream)
│   ├── group_files/
│   │   ├── kardi_monitoring/       # Prometheus/Alertmanager configs, group-specific nginx templates
│   │   ├── kardi_proxy/            # proxy nginx template (kardi-proxy.conf.j2)
│   │   └── shared/                 # nginx base config shared by all hosts
│   └── host_files/
│       ├── sg.mon.kardi-ai.org/    # node_exporter_targets.yml, web-targets.yml
│       └── de.mon.kardi-ai.org/    # node_exporter_targets.yml, web-targets.yml
├── playbooks/
│   ├── kardi-monitoring.yml
│   ├── kardi-proxy.yml
│   └── uptime-kuma.yml
├── roles/                          # custom Ansible roles
└── vault-setup.sh                  # helper script for setting vault password
```
