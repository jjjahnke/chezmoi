# Allow read-only access to secrets required by chezmoi templates
path "secret/data/personal/aws/*" {
  capabilities = ["read"]
}
path "secret/data/kube/personal/gpu-server" {
  capabilities = ["read"]
}
path "secret/data/personal/api-keys" {
  capabilities = ["read"]
}
