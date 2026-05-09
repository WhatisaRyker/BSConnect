# ─────────────────────────────────────────
# BSConnect Infra Makefile
# Run from the /infra directory
# ─────────────────────────────────────────

.PHONY: up down dev logs ps clean vault-init

# Production stack (no dev tools)
up:
	docker compose -f docker-compose.yml up -d

# Development stack (adds pgadmin, redis-commander, exposed ports)
dev:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# Stop all containers
down:
	docker compose -f docker-compose.yml down

# Follow logs (optionally pass service= to filter)
logs:
	docker compose -f docker-compose.yml logs -f $(service)

# Show running containers
ps:
	docker compose -f docker-compose.yml ps

# Remove all containers AND volumes (destructive — wipes all data)
clean:
	docker compose -f docker-compose.yml down -v

# Initialize Vault (run once after first `make up`)
vault-init:
	chmod +x ./vault/init-vault.sh && ./vault/init-vault.sh
