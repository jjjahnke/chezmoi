# Declarative Development Environment

This repository contains the configuration for a declarative and reproducible development environment, managed by [chezmoi](httpshttps://www.chezmoi.io/).

## Overview

This setup is designed to automate the provisioning of a consistent development environment across multiple machines (macOS and Linux). It follows the principles of "Environment as Code" to ensure that the entire setup is version-controlled, auditable, and easily portable.

The architecture consists of two main parts:

1.  **Imperative Bootstrap Script (`bootstrap.sh`):** An idempotent script that installs the foundational toolchains and dependencies required on a new machine. This includes Homebrew, Go, Node.js (via nvm), Python (via pyenv), AWS CLI, and `chezmoi` itself.
2.  **Declarative Configuration (chezmoi):** `chezmoi` manages the dotfiles, applying templates to generate machine-specific configurations and securely managing secrets with a backend like HashiCorp Vault.

## Quick Start

1.  **Bootstrap a new machine:**

    ```bash
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jjjahnke/chezmoi/main/bootstrap.sh)"
    ```

2.  **Initialize the declarative environment:**

    After the bootstrap is complete, initialize `chezmoi` to apply the configurations from this repository:

    ```bash
    chezmoi init --apply jjjahnke
    ```

This will clone the repository, execute the templates, fetch any required secrets, and apply the final state to your home directory.