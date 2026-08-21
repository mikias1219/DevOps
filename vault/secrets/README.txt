Vault secrets directory (gitignored except *.example)

After `./vault/scripts/bootstrap.sh`:
  vault-keys.env       unseal key + root token
  vault-approle.env    AppRole for export scripts
  operator-login.txt   UI username/password

chmod 700 this directory; chmod 600 files inside.
