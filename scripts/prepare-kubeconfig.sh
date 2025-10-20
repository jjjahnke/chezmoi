#!/bin/bash
#
# prepare-kubeconfig.sh: Converts a standard kubeconfig file into a chezmoi
# template and a set of Vault commands for storing the secrets.
#

set -euo pipefail

# --- Help/Usage Function ---
usage() {
  cat <<EOF
Usage: $(basename "$0") -c <work|personal> -n <cluster-name> [-i <input-file>]

This script converts a kubeconfig file into a chezmoi template and a companion
script to upload the secrets to HashiCorp Vault.

OPTIONS:
  -c <context>    Required. The context for the secret path ('work' or 'personal').
  -n <name>       Required. A short name for the cluster. Used for the Vault path
                  and the output filename.
  -i <file>       Optional. The path to the input kubeconfig file. If not provided,
                  the script will read from standard input.
  -h              Show this help message.

DEPENDENCIES:
  - yq (version 4+): A command-line YAML processor. Install via Homebrew or from
    https://github.com/mikefarah/yq/

EXAMPLE:
  cat my-cluster.yaml | $(basename "$0") -c personal -n my-cluster
  $(basename "$0") -c work -n production -i /path/to/prod.config
EOF
  exit 1
}

# --- Argument Parsing ---
CONTEXT=""
CLUSTER_NAME=""
INPUT_FILE=""

while getopts "c:n:i:h" opt; do
  case $opt in
    c) CONTEXT="$OPTARG" ;;
    n) CLUSTER_NAME="$OPTARG" ;;
    i) INPUT_FILE="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

# --- Validation ---
if [[ -z "$CONTEXT" ]] || [[ -z "$CLUSTER_NAME" ]]; then
  echo "Error: Missing required arguments." >&2
  usage
fi

if [[ "$CONTEXT" != "work" ]] && [[ "$CONTEXT" != "personal" ]]; then
  echo "Error: Context must be either 'work' or 'personal'." >&2
  usage
fi

if ! command -v yq &>/dev/null; then
  echo "Error: 'yq' is not installed. Please install it to continue." >&2
  echo "See: https://github.com/mikefarah/yq/" >&2
  exit 1
fi

# --- Read Input ---
KUBECONFIG_CONTENT=""
if [[ -n "$INPUT_FILE" ]]; then
  if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: Input file not found: $INPUT_FILE" >&2
    exit 1
  fi
  KUBECONFIG_CONTENT=$(cat "$INPUT_FILE")
else
  echo "Reading kubeconfig from standard input..." >&2
  KUBECONFIG_CONTENT=$(cat)
fi

# --- Main Logic ---
VAULT_BASE_PATH="secret/kube/${CONTEXT}/${CLUSTER_NAME}"
VAULT_COMMANDS_FILE="vault_commands_for_${CLUSTER_NAME}.sh"
CHEZMOI_TEMPLATE_FILE="private_dot_kube/configs/${CLUSTER_NAME}.yaml.tmpl"

# A space-separated list of sensitive keys to search for.
SENSITIVE_KEYS_LIST="certificate-authority-data client-certificate-data client-key-data token"

# Initialize files
echo "#!/bin/bash" > "$VAULT_COMMANDS_FILE"
echo "# This script contains the command to upload secrets for the '${CLUSTER_NAME}' cluster." >> "$VAULT_COMMANDS_FILE"
echo "# Review carefully before executing." >> "$VAULT_COMMANDS_FILE"
chmod +x "$VAULT_COMMANDS_FILE"

MODIFIED_KUBECONFIG="$KUBECONFIG_CONTENT"
VAULT_KV_PAIRS=""

# Process clusters
for key in $SENSITIVE_KEYS_LIST; do
  vault_key=""
  case "$key" in
    "certificate-authority-data") vault_key="ca_crt" ;;
    "client-certificate-data")    vault_key="client_crt" ;;
    "client-key-data")            vault_key="client_key" ;;
    "token")                      vault_key="token" ;;
  esac

  yq_path=".clusters[].cluster.\"${key}\""
  if [[ $(echo "$MODIFIED_KUBECONFIG" | yq e "$yq_path") != "null" ]]; then
    secret_value=$(echo "$MODIFIED_KUBECONFIG" | yq e "$yq_path")
    VAULT_KV_PAIRS="${VAULT_KV_PAIRS} ${vault_key}=\"${secret_value}\""
    MODIFIED_KUBECONFIG=$(echo "$MODIFIED_KUBECONFIG" | yq e "(${yq_path}) |= \"{{ (vault \\\"${VAULT_BASE_PATH}\\\").data.data.${vault_key} }}\"")
    echo "Found and replaced '${key}' in clusters..." >&2
  fi
done

# Process users
for key in $SENSITIVE_KEYS_LIST; do
  vault_key=""
  case "$key" in
    "certificate-authority-data") vault_key="ca_crt" ;;
    "client-certificate-data")    vault_key="client_crt" ;;
    "client-key-data")            vault_key="client_key" ;;
    "token")                      vault_key="token" ;;
  esac

  yq_path=".users[].user.\"${key}\""
  if [[ $(echo "$MODIFIED_KUBECONFIG" | yq e "$yq_path") != "null" ]]; then
    secret_value=$(echo "$MODIFIED_KUBECONFIG" | yq e "$yq_path")
    VAULT_KV_PAIRS="${VAULT_KV_PAIRS} ${vault_key}=\"${secret_value}\""
    MODIFIED_KUBECONFIG=$(echo "$MODIFIED_KUBECONFIG" | yq e "(${yq_path}) |= \"{{ (vault \\\"${VAULT_BASE_PATH}\\\").data.data.${vault_key} }}\"")
    echo "Found and replaced '${key}' in users..." >&2
  fi
done

# Write the single, consolidated Vault command
if [[ -n "$VAULT_KV_PAIRS" ]]; then
  echo "vault kv put ${VAULT_BASE_PATH}${VAULT_KV_PAIRS}" >> "$VAULT_COMMANDS_FILE"
fi

# --- Write Output Files ---
mkdir -p "$(dirname "$CHEZMOI_TEMPLATE_FILE")"
echo "$MODIFIED_KUBECONFIG" > "$CHEZMOI_TEMPLATE_FILE"

# --- Final Instructions ---
cat <<EOF

---------------------------------------------------------------------
Processing Complete!

1.  **Vault Commands Generated:**
    A script named '${VAULT_COMMANDS_FILE}' has been created.
    ==> REVIEW THIS FILE CAREFULLY, then execute it to upload the secrets to Vault.

2.  **Chezmoi Template Created:**
    The new template is located at '${CHEZMOI_TEMPLATE_FILE}'.
    ==> Add, commit, and push this file to your chezmoi repository.

After completing these steps and running 'chezmoi apply', the new cluster
context will be available.
---------------------------------------------------------------------
EOF
