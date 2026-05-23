# BSConnect Infrastructure

## Structure

```
infra/
├── docker-compose.yml          # Production stack
├── docker-compose.dev.yml      # Dev overrides (extra tools, exposed ports)
├── .env.example                # Copy to .env and fill in secrets
├── Makefile                    # Common commands
├── vault/
│   ├── vault.hcl               # Vault server config
│   └── init-vault.sh           # One-time init script
├── postgres/
│   └── init.sql                # Schema, roles, RLS policies
├── prometheus/
│   └── prometheus.yml          # Scrape config
└── grafana/
    └── provisioning/
        └── datasources/
            └── prometheus.yml  # Auto-configured Prometheus datasource
```

## First-Time Setup

### 1. Create your .env file
```bash
cp .env.example .env
# Edit .env with real secrets — never commit this file
```

### 2. Start the stack
```bash
make up           # production
make dev          # development (adds pgadmin, redis-commander)
```

### 3. Initialize Vault (once only)
```bash
make vault-init
```
This will print your `VAULT_TOKEN`. Add it to `.env` and **move the generated `vault-init.json` off the server immediately** — it contains your unseal keys.

### 4. Restart the API so it picks up the Vault token
```bash
docker compose restart api
```

## Dev Tools (dev stack only)

| Tool            | URL                    | Credentials         |
|-----------------|------------------------|---------------------|
| PgAdmin         | http://localhost:5050  | See .env            |
| Redis Commander | http://localhost:8081  | No login            |
| Grafana         | http://localhost:3000  | admin / See .env    |
| Prometheus      | http://localhost:9090  | No login            |
| Vault UI        | http://localhost:8200  | Dev token           |

