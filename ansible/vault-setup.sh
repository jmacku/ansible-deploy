#!/usr/bin/env bash
export ANSIBLE_VAULT_PASSWORD_FILE=${PWD}/valut-env.sh

echo "Provide ANSIBLE_VAULT_PASSWORD: "
read -s ANSIBLE_VAULT_PASSWORD && export ANSIBLE_VAULT_PASSWORD