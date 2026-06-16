## Vault password
Provide password for ansible-vault form environement variable `ANSIBLE_VAULT_PASSWORD`
```shell
export ANSIBLE_VAULT_PASSWORD_FILE=~/bin/vault-env
```

```shell
-> % cat ~/bin/vault-env                
#!/bin/bash
echo $ANSIBLE_VAULT_PASSWORD
```

```shell
read -s ANSIBLE_VAULT_PASSWORD && export ANSIBLE_VAULT_PASSWORD

# check if needed 
env | grep ANSIBLE
```
Then run the playbook
```shell
ansible-playbook playbooks/kardi-monitoring.yml

## limit to only specific host 

## limit where to start
ansible-playbook playbooks/kardi-monitoring.yml --start-at-task="Copy Prometheus config"
```