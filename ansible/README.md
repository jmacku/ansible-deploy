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
read -s ANSIBLE_VAULT_PASSWORD
export ANSIBLE_VAULT_PASSWORD
# check 
env | grep ANSIBLE
```
