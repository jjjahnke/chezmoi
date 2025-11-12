# Specification: Native `chezmoi` Vault Integration

**Status:** Not Started

## Overview

This repository currently uses a shell script (`repopulate_vault.sh`) to manage the `chezmoi-readonly` policy in Vault. This is effective, but it creates a disconnect between the `chezmoi` configuration and the Vault policy that governs it.

`chezmoi` has a built-in feature to manage Vault policies directly, typically from a `chezmoi-policy.hcl` file.

## Goal

The goal of this task is to investigate and potentially implement `chezmoi`'s native Vault integration for policy management.

## Proposed Steps

1.  **Research:** Review the official `chezmoi` documentation for managing Vault policies.
2.  **Prototype:** Create a `chezmoi-policy.hcl` file that replicates the policy currently defined in `repopulate_vault.sh`.
3.  **Test:** In a test environment, configure `chezmoi` to apply this policy to the Vault server.
4.  **Refactor:** If successful, remove the policy definition from `repopulate_vault.sh` and update the documentation to reflect the new, native workflow.
