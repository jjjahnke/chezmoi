# Specification: Bootstrapping HashiCorp Vault in Kubernetes

**Status:** To Be Done

## 1. Overview

This document provides a complete, step-by-step guide for deploying and configuring a production-ready HashiCorp Vault instance within a Kubernetes cluster. This setup is the foundational prerequisite for the entire declarative environment, as it serves as the central secret store for both Ansible provisioning and `chezmoi`'s ongoing operations.

The goal is to create a persistent, unsealed, and network-accessible Vault server, ready to be populated with the necessary secrets, policies, and authentication roles.

## 2. Prerequisites

- A running Kubernetes cluster.
- `kubectl` installed and configured to connect to your cluster.
- `helm` (version 3+) installed.
- A DNS server on your local network (e.g., Pi-hole) capable of creating local DNS records.

## 3. Installation via Helm

We will use the official HashiCorp Helm chart to deploy Vault.

### Step 3.1: Add the HashiCorp Helm Repository

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

### Step 3.2: Create a `values.yaml` for Configuration

Create a file named `vault-values.yaml` with the following content. This configures a simple, single-node Vault instance with persistent storage, which is suitable for this use case.

```yaml
# vault-values.yaml
server:
  # Run a single, non-HA instance.
  ha:
    enabled: false
  
  # Use a PersistentVolumeClaim to store Vault's data.
  dataStorage:
    enabled: true
    size: 1Gi
    # storageClass: <your-storage-class> # Uncomment and set if needed
```

### Step 3.3: Install the Helm Chart

Run the following command to deploy Vault into its own `vault` namespace.

```bash
kubectl create namespace vault
helm install vault hashicorp/vault --namespace vault -f vault-values.yaml
```
Wait for the `vault-0` pod to be in the `Running` state before proceeding.

## 4. Initialization and Unsealing

The new Vault instance starts in a **sealed** state. We need to initialize it to get the cryptographic keys and then unseal it to make it operational.

### Step 4.1: Initialize Vault

Get a shell inside the `vault-0` pod and run the `vault operator init` command.

```bash
kubectl exec -it -n vault vault-0 -- vault operator init
```

> **CRITICAL WARNING:**
> This command will output the **Unseal Keys** and the **Initial Root Token**. You **MUST** save these in a secure location (like a password manager). If you lose them, you will lose all data in Vault. You will need at least 3 of the 5 unseal keys to unseal Vault in the future.

### Step 4.2: Unseal Vault

To make Vault operational, you must unseal it. Run the following command three times, each time pasting one of the Unseal Keys you saved from the previous step when prompted.

```bash
# Run this command three times
kubectl exec -it -n vault vault-0 -- vault operator unseal
```
After the third key is entered, the output will show `Sealed: false`. Your Vault is now operational.

## 5. Exposing Vault to the Network

By default, Vault is only accessible from inside the cluster. We will use a Traefik `IngressRoute` to expose it.

### Step 5.1: Create the IngressRoute

Apply the `vault-ingress.yaml` manifest to your cluster. This tells Traefik how to route traffic to the Vault service.

```bash
kubectl apply -f vault-ingress.yaml
```

### Step 5.2: Configure DNS

In your local DNS server (e.g., Pi-hole), create a DNS record that points the hostname `vault.lan` to the IP address of your Traefik load balancer (`192.168.150.210`).

## 6. Populating and Configuring for `chezmoi`

Now that Vault is running and accessible, we need to populate it with the secrets, policies, and roles required by your automation.

### Step 6.1: Run the Repopulation Script

This script is the source of truth for all your secrets and the `chezmoi-readonly` policy.

1.  Copy the template: `cp repopulate_vault.sh.tmpl repopulate_vault.sh`
2.  Edit `repopulate_vault.sh` and fill in all the `REPLACE_WITH_...` placeholder values with your actual secrets.
3.  Run the script using your **new root token**:
    ```bash
    export VAULT_ADDR="http://vault.lan:8000"
    export VAULT_TOKEN="s.YourNewRootToken"
    ./repopulate_vault.sh
    ```

### Step 6.2: Set up the AppRoles

This script creates the `chezmoi-vm` and `dev-role` AppRoles that your automation relies on.

```bash
# Use the same VAULT_ADDR and VAULT_TOKEN from the previous step
./scripts/setup-vault-approle.sh
```

## 7. Conclusion

At the end of this process, you will have a fully configured Vault server, accessible at `http://vault.lan:8000`, populated with all your necessary data, and ready to be used by your Ansible provisioning playbook.
