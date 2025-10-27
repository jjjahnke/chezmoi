# Bootstrapping VMs with Secure, Automated Secret Management

This document outlines the entire workflow for provisioning VMs with `chezmoi` and securely connecting them to HashiCorp Vault for secret management.

## Core Concept

The goal is to allow `chezmoi` on provisioned VMs to automatically and securely fetch secrets (like API keys) from Vault without ever storing a powerful, long-lived token on the VM.

This is achieved using Vault's **AppRole Authentication Method**, which allows a machine to be given a unique, limited-privilege identity to programmatically fetch its own temporary tokens.

## The Workflow

The entire process is automated by Ansible.

1.  **Ansible Authentication:** The `invoke_playbook.sh` script uses a password to decrypt `secrets.yml`, which contains the powerful **Vault root token**. This token is used *only* by Ansible during the provisioning process.

2.  **VM Provisioning:** The `install_git.yml` playbook connects to the target VM and performs the following Vault-related steps:
    a. It uses the root token to request a unique, machine-specific identity from Vault. This identity consists of a `RoleID` and a `SecretID`.
    b. It securely writes these two credentials to a file on the VM at `~/.vault-credentials`. This file is locked down with `0600` permissions.

3.  **Automatic Login on the VM:** The `.zshrc` file on the VM is configured with a script that runs every time a new shell is opened.
    a. The script sources the credentials from `~/.vault-credentials`.
    b. It uses these credentials to log in to Vault via the AppRole method.
    c. Vault verifies the credentials, checks that they are tied to the `chezmoi-readonly` policy, and issues a new, temporary, and limited-privilege token.
    d. The script exports this temporary token into the `VAULT_TOKEN` environment variable.

4.  **Seamless `chezmoi` Execution:** When you run `chezmoi update` or `chezmoi apply`, it automatically finds the `VAULT_ADDR` and the temporary `VAULT_TOKEN` in the environment and can successfully read the secrets it needs.

## How to Use

To provision a new VM, simply run the script from the root of this repository with the IP address(es) of the target machine(s).

```bash
./invoke_playbook.sh 192.168.1.100
```

## Managing the System

### Vault Server

*   The Vault server is deployed via Helm in Kubernetes.
*   It runs in a persistent, single-node configuration on the master node for stability.
*   It is exposed to the internal network via a `NodePort` service on port `30200`.

### Updating the Vault Root Token

If the Vault root token is ever changed, you must update it in the encrypted `secrets.yml` file.

1.  **Edit the file:** `ansible-vault edit secrets.yml`
2.  **Enter the password:** You will be prompted for the Ansible Vault password (the one stored in `invoke_playbook.sh`).
3.  **Update the token:** Your editor will open with the decrypted content. Update the `vault_token` value, save, and quit. The file will be automatically re-encrypted.

### Modifying VM Permissions

If your `chezmoi` templates ever need to access new secret paths, you must update the `chezmoi-readonly` policy in Vault.

1.  **Edit the policy file:** Open `chezmoi-policy.hcl` and add the new path and capabilities.
2.  **Apply the policy to Vault:**
    ```bash
    # Ensure VAULT_TOKEN is set to your root token
    export VAULT_TOKEN="hvs.pMx..."

    # Write the policy
    vault policy write chezmoi-readonly chezmoi-policy.hcl
    ```
