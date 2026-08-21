# HashiCorp Vault — single-node file storage + UI (not -dev mode)
# Data: Docker volume vault_data
# After first start: run vault/scripts/bootstrap.sh once

ui = true
disable_mlock = true

storage "file" {
  path = "/vault/file"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = 1
}

api_addr     = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"
