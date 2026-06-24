#!/usr/bin/env bash
export ANSIBLE_VAULT_PASSWORD_FILE=${PWD}/vault-env.sh

echo "Provide ANSIBLE_VAULT_PASSWORD: "
read -sr ANSIBLE_VAULT_PASSWORD && export ANSIBLE_VAULT_PASSWORD