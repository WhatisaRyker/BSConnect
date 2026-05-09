#!/bin/bash
# Vault Init Script
# Run this ONCE after first `docker compose up`.
# Saves unseal keys and root token to vault-init.json — store these securely.

set -e

VAULT_ADDR="http://localhost:8200"

echo "Waiting for Vault to be ready..."
until curl -sf "$VAULT_ADDR/v1/sys/health" > /dev/null 2>&1; do
  sleep 2
done

echo "Initializing Vault..."
INIT_OUTPUT=$(curl -sf \
  --request POST \
  --data '{"secret_shares": 3, "secret_threshold": 2}' \
  "$VAULT_ADDR/v1/sys/init")

echo "$INIT_OUTPUT" > vault-init.json
echo "Init output saved to vault-init.json — STORE THIS FILE SECURELY AND DELETE IT FROM THIS SERVER"

# Extract keys and token
KEY1=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['keys'][0])")
KEY2=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['keys'][1])")
ROOT_TOKEN=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['root_token'])")

echo "Unsealing Vault..."
curl -sf --request POST --data "{\"key\": \"$KEY1\"}" "$VAULT_ADDR/v1/sys/unseal" > /dev/null
curl -sf --request POST --data "{\"key\": \"$KEY2\"}" "$VAULT_ADDR/v1/sys/unseal" > /dev/null

echo "Enabling transit secrets engine..."
curl -sf \
  --header "X-Vault-Token: $ROOT_TOKEN" \
  --request POST \
  --data '{"type":"transit"}' \
  "$VAULT_ADDR/v1/sys/mounts/transit" > /dev/null

echo "Creating message encryption key..."
curl -sf \
  --header "X-Vault-Token: $ROOT_TOKEN" \
  --request POST \
  --data '{"type":"aes256-gcm96"}' \
  "$VAULT_ADDR/v1/transit/keys/message-key" > /dev/null

echo "Creating API policy..."
curl -sf \
  --header "X-Vault-Token: $ROOT_TOKEN" \
  --request POST \
  --data '{
    "policy": "path \"transit/encrypt/message-key\" { capabilities = [\"update\"] } path \"transit/decrypt/message-key\" { capabilities = [\"update\"] } path \"transit/keys/message-key\" { capabilities = [\"read\"] }"
  }' \
  "$VAULT_ADDR/v1/sys/policies/acl/api-policy" > /dev/null

echo "Creating API token..."
API_TOKEN=$(curl -sf \
  --header "X-Vault-Token: $ROOT_TOKEN" \
  --request POST \
  --data '{"policies": ["api-policy"], "ttl": "720h", "renewable": true}' \
  "$VAULT_ADDR/v1/auth/token/create" | python3 -c "import sys,json; print(json.load(sys.stdin)['auth']['client_token'])")

echo ""
echo "Vault initialized and configured"
echo "API Token (add this to your .env as VAULT_TOKEN):"
echo "  $API_TOKEN"
echo ""
echo "vault-init.json contains your unseal keys — move it off this server immediately."
