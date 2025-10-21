# Declarative Development Environment

[![Environment as Code](https://img.shields.io/badge/methodology-Environment%20as%20Code-blue)](https://www.chezmoi.io/) [![Managed by chezmoi](https://img.shields.io/badge/managed%20by-chezmoi-brightgreen)](https://www.chezmoi.io/) [![Secrets with Vault](https://img.shields.io/badge/secrets-HashiCorp%20Vault-lightgrey)](https://www.hashicorp.com/products/vault)

This repository contains the complete configuration for a declarative, reproducible, and secure development environment. It is built on the "Environment as Code" methodology, where the entire state of the environment is version-controlled in Git, enabling consistent and automated setup across multiple diverse machines and platforms.

## Overview

The core objective of this architecture is to eliminate manual configuration and the "it works on my machine" problem. By combining an idempotent bootstrap script with the declarative power of `chezmoi` and the security of HashiCorp Vault, this system provides a robust framework for managing dotfiles, development tools, and secrets across any number of ephemeral or long-lived environments.

### Key Features

*   **Fully Automated Setup:** Go from a bare OS (macOS or Linux) to a fully provisioned development environment with two commands.
*   **Declarative State Management:** `chezmoi` is used to manage the desired state of configuration files, ensuring consistency and predictability.
*   **Powerful Templating:** Configurations are generated dynamically based on machine-specific attributes (e.g., OS, hostname, work vs. personal), allowing a single source of truth to manage multiple contexts.
*   **Secure Secret Management:** All sensitive data (API keys, credentials) is managed out-of-band in **HashiCorp Vault**. Secrets are fetched in-memory during configuration application and are never stored in the Git repository. This includes support for context-aware secrets, allowing for different credentials to be applied based on a machine's role (e.g., "work" or "personal").
*   **Cross-Platform & Ephemeral:** Designed for consistency across macOS, Linux, bare-metal servers (PXE boot), Docker containers, and Kubernetes pods.
*   **Auditable and Version-Controlled:** Every change to the environment's configuration is tracked in Git history, providing a full audit trail and the ability to review or revert changes.

## Architecture

The system is designed in two distinct phases to ensure a clean separation of concerns between initial system provisioning and ongoing configuration management.

### Part I: The Foundational Bootstrap

An idempotent, non-interactive bootstrap script (`bootstrap.sh`) prepares a new machine with the essential, foundational toolchains. This script can be run multiple times without causing errors and ensures the system has all prerequisites for declarative management.

Its responsibilities include:
- **Package Manager Setup:** Installs **Homebrew** on macOS or Linux.
- **Core Dependencies:** Installs essential build tools (`build-essential`, `xcode-select`, etc.).
- **Development Toolchains:**
    - **Go** (user-local installation)
    - **Node.js** (via `nvm`)
    - **Python** (via `pyenv`)
- **Core Utilities:** Installs the **AWS CLI v2** and **chezmoi**.

### Part II: Declarative Environment Management

Once the bootstrap is complete, **`chezmoi`** takes over as the declarative orchestration engine. It performs the following actions:
1.  **Clones** this Git repository to serve as the single source of truth.
2.  **Computes the desired state** by executing Go templates (`.tmpl` files), generating machine-specific configurations.
3.  **Injects secrets** by calling out to **HashiCorp Vault** in memory.
4.  **Applies the state** to the home directory, creating dotfiles, setting permissions, and running scripts to bring the environment into compliance.

## Getting Started

Provisioning a new machine is a simple, two-step process.

### Prerequisites
- A fresh macOS or Linux (Debian/Ubuntu or Fedora/CentOS) environment.
- Git must be installed.

### 1. Execute the Bootstrap Script

Run the following command in your terminal to install all foundational tools:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jjjahnke/chezmoi/main/bootstrap.sh)"
```

This script is idempotent and will safely install only the missing components.

### 2. Initialize the Declarative Environment

With the prerequisites installed, run the `chezmoi` command below to apply the personalized configuration from this repository. `chezmoi` will prompt for any information needed to configure the machine for its context (e.g., work vs. personal).

```bash
chezmoi init --apply jjjahnke/chezmoi
```

At the conclusion of this step, your machine will be a perfect, ready-to-use replica of the defined development environment.

## Daily Workflow: Managing Your Environment as Code

All changes to the environment follow a structured, version-controlled Git workflow.

1.  **Edit a file:** Use `chezmoi edit ~/.<filename>` to open the source template in your editor.
    ```bash
    chezmoi edit ~/.gitconfig
    ```
2.  **Preview changes:** See what changes will be made before applying them.
    ```bash
    chezmoi diff
    ```
3.  **Apply changes locally:** Apply the new state to the local machine.
    ```bash
    chezmoi apply
    ```
4.  **Commit and push:** Once satisfied, commit the changes to the source of truth and push them to the remote repository.
    ```bash
    chezmoi cd && git add .
    git commit -m "Update git config with new alias"
    git push
    ```
5.  **Synchronize other machines:** On any other machine, pull and apply the latest changes with a single command.
    ```bash
    chezmoi update
    ```

## Managing Kubernetes Configurations

This setup uses a multi-file approach for Kubernetes configurations, where each cluster has its own config file. The `KUBECONFIG` environment variable is automatically managed to include all files from the `~/.kube/configs` directory.

To add a new cluster configuration, follow these steps:

1.  **Place the Config File:** Take your new `kubeconfig` file and place it inside the `private_dot_kube/configs/` directory in this repository. For example, name it `my-new-cluster.yaml`.

2.  **Convert to a Template:** Rename the file to end with `.tmpl`.
    ```bash
    mv private_dot_kube/configs/my-new-cluster.yaml private_dot_kube/configs/my-new-cluster.yaml.tmpl
    ```

3.  **Secure the Secrets:** Edit the new `.tmpl` file and replace any sensitive information (like `token`, `client-key-data`, or `client-certificate-data`) with `chezmoi`'s `vault` template function.

    **Example:**

    Before (original `kubeconfig`):
    ```yaml
    # ...
    users:
    - name: my-user
      user:
        token: "THIS_IS_A_VERY_SECRET_TOKEN"
    # ...
    ```

    After (in your `.tmpl` file):
    ```go-template
    # ...
    users:
    - name: my-user
      user:
        token: "{{ (vault "secret/kube/my-new-cluster").data.data.token }}"
    # ...
    ```
    *Note: You must first store the secret (`token` in this case) in your HashiCorp Vault at the specified path (`secret/kube/my-new-cluster`).*

After adding the file and running `chezmoi apply`, the new cluster context will be automatically available to `kubectl`, `kubectx`, and other Kubernetes tools.

## Containerized and Cloud-Native Environments

This architecture extends seamlessly to ephemeral environments.

-   **Docker:** A pattern using `chezmoi init --one-shot` is provided in the design documents to build fully-configured, self-contained Docker images.
-   **Kubernetes:** The system can be integrated with Kubernetes Init Containers to configure a pod's environment at runtime. For secret management, the recommended pattern is to use the **External Secrets Operator** to synchronize secrets from Vault into native Kubernetes Secret objects.

## Building the Dockerized Environment

This repository includes a `Dockerfile` to build a self-contained, pre-baked development environment with all tools installed.

### Prerequisites

*   Docker with `buildx` enabled (this is the default on modern Docker Desktop installations).

### Building for a Single Architecture (e.g., on your local machine)

This is the standard build command. It will create an image that matches the architecture of your current machine.

```bash
# On an Apple Silicon Mac, this builds an arm64 image.
# On a Linux AMD64 machine, this builds an amd64 image.
docker build -t jahnke/dev-env:latest .
```

### Building a Multi-Arch Image (for use on both Mac and Linux)

To create a single image tag that works on both `arm64` (Apple Silicon) and `amd64` (Linux/Intel) machines, use the `docker buildx` command. This command builds the image for both architectures and pushes them to a container registry.

When a user on an Apple Silicon Mac runs `docker pull jahnke/dev-env:latest`, Docker will automatically download the `arm64` variant. When a user on a Linux machine does the same, Docker will pull the `amd64` variant.

```bash
# 1. Create a new builder instance (only needs to be done once)
docker buildx create --name multi-arch-builder --use

# 2. Build and push the multi-arch image to a registry
# (Replace 'jahnke' with your Docker Hub username or registry)
docker buildx build --platform linux/amd64,linux/arm64 -t jahnke/dev-env:latest --push .
```
*Note: You must `--push` a multi-arch image; you cannot load it directly into your local Docker daemon.*
