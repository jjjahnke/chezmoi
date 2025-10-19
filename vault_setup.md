# Deploying Vault in Dev Mode to Kubernetes

This guide outlines the steps to deploy a non-production, development-mode Vault server to a Kubernetes cluster using the official HashiCorp Helm chart.

**Note:** This configuration is for testing and development purposes only. It is not secure for production use as it uses an in-memory file system and exposes the service via a NodePort.

## Step 1: Add the HashiCorp Helm Repository

First, add the HashiCorp Helm repository to your local Helm client and update it to fetch the latest chart information.

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

## Step 2: Deploy Vault in Dev Mode

Use the following command to install a `dev` mode Vault instance. This will create a new `vault` namespace and expose the service on a `NodePort` for easy access from outside the cluster.

```bash
helm install vault hashicorp/vault \
  --create-namespace \
  --namespace vault \
  --set "server.dev.enabled=true" \
  --set "server.service.type=NodePort" \
  --set "server.service.nodePort=30200"
```

## Step 3: Retrieve Vault Address and Token

Once the Vault pod is running, you will need to retrieve its address and the root token to interact with it.

### Get the Vault Address (`VAULT_ADDR`)

1.  Find the IP address of any of your Kubernetes nodes.
    ```bash
    kubectl get nodes -o wide
    ```
2.  Your `VAULT_ADDR` will be `http://<NODE_IP>:30200`, where `<NODE_IP>` is the internal or external IP of one of your nodes.

### Get the Vault Token (`VAULT_TOKEN`)

1.  The development server starts with a default root token. You can retrieve it by checking the logs of the `vault-0` pod.
    ```bash
    kubectl logs vault-0 -n vault
    ```
2.  Look for a line in the logs that says `Root Token:`. The value that follows is your `VAULT_TOKEN` (the default is often `root`).

You can now use these values to configure your environment and applications to communicate with Vault.
