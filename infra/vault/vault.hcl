# ─────────────────────────────────────────
# HashiCorp Vault Configuration
# Production mode — file storage backend
# ─────────────────────────────────────────

storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true   # TLS terminated at Nginx/Cloudflare — internal only
}

# How long a token is valid without renewal
default_lease_ttl = "168h"   # 7 days
max_lease_ttl     = "720h"   # 30 days

# Prevents memory from being swapped to disk
disable_mlock = false

# API address used for redirects and cluster coordination
api_addr = "http://vault:8200"

ui = false   # disable the web UI in production
