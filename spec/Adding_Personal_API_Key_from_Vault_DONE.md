# Specification: Adding a Personal API Key from Vault

**Status:** Completed (2025-10-19)

This document outlines the steps required to add a new personal environment variable, `GEMINI_API_KEY`, to the declarative environment. The value for this key will be securely sourced from HashiCorp Vault and will only be applied to machines designated as "personal".

This process adheres to the established architectural pattern of separating configurations and secrets based on the machine's context (i.e., "work" vs. "personal").

## Implementation Steps

1.  **Store the Secret in Vault:**
    *   The new API key must be stored in a Vault path designated for personal secrets to maintain the separation of concerns.
    *   **Path:** `secret/personal/api-keys`
    *   **Key:** `gemini_api_key`
    *   **Action:** Add the secret value to Vault at the specified path.

2.  **Update the Shell Configuration Template:**
    *   The `dot_zshrc.tmpl` file will be modified to conditionally export the `GEMINI_API_KEY`.
    *   **File to Edit:** `dot_zshrc.tmpl`
    *   **Logic:** A template condition will check the machine's context (e.g., `{{ if ne .machineType "work" }}`). The environment variable will only be exported if the machine is *not* a "work" machine.
    *   **Code Snippet to Add:**
        ```go-template
        {{ if ne .machineType "work" -}}
        # Personal Environment Variables
        export GEMINI_API_KEY="{{ (vault "secret/personal/api-keys").data.data.gemini_api_key }}"
        {{- end }}
        ```

3.  **Apply and Verify:**
    *   After modifying the template, run `chezmoi apply` on a designated "personal" machine.
    *   Verify that the `~/.zshrc` file is updated with the `export GEMINI_API_KEY=...` line.
    *   Run `chezmoi apply` on a "work" machine to verify that the `~/.zshrc` file is *not* modified with this new key.

4.  **Commit and Propagate:**
    *   Once the change is verified, commit the modification to the `dot_zshrc.tmpl` file to the Git repository.
    *   This makes the change permanent and allows it to be propagated to all other managed machines via `chezmoi update`.
