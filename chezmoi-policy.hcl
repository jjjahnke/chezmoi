# Grant read-only access to the KVv2 secrets engine mounted at "secret/".
# The vault CLI requires access to both the data and metadata paths to function.

# Allow reading the secret data
path "secret/data/personal/aws/*" {
  capabilities = ["read", "list"]
}
path "secret/data/kube/personal/gpu-server" {
  capabilities = ["read", "list"]
}
path "secret/data/personal/api-keys" {
  capabilities = ["read", "list"]
}

# Allow reading the secret metadata
path "secret/metadata/personal/aws/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/kube/personal/gpu-server" {
  capabilities = ["read", "list"]
}
path "secret/metadata/personal/api-keys" {
  capabilities = ["read", "list"]
}
