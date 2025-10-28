#!/bin/bash
#
# A bootstrap script for setting up a new macOS or Linux machine.
#
# This script is designed to be idempotent and non-interactive.
# It can be run multiple times on the same machine without causing
# errors or unintended side effects.

set -e

# --- Helper Functions ---

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to add a line to a file if it doesn't already exist
add_line_to_file() {
  local line="$1"
  local file="$2"
  if ! grep -qF -- "$line" "$file"; then
    echo "Adding '$line' to $file"
    echo -e "\n$line" >> "$file"
  else
    echo "'$line' already exists in $file."
  fi
}

# --- OS Detection ---

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  'Linux')
    if [ -f /etc/os-release ]; then
      . /etc/os-release
      DISTRO=$ID
    else
      echo "Unsupported Linux distribution."
      exit 1
    fi
    ;;
  'Darwin')
    DISTRO='macOS'
    ;;
  *)
    echo "Unsupported operating system: $OS"
    exit 1
    ;;
esac

echo "Detected OS: $DISTRO ($ARCH)"

# --- Shell Profile Detection ---

if [ -n "$BASH_VERSION" ]; then
    PROFILE_FILE="$HOME/.bashrc"
elif [ -n "$ZSH_VERSION" ]; then
    PROFILE_FILE="$HOME/.zshrc"
else
    # Fallback for other shells, might need adjustment
    PROFILE_FILE="$HOME/.profile"
fi

if [ ! -f "$PROFILE_FILE" ]; then
    touch "$PROFILE_FILE"
fi

echo "Using shell profile: $PROFILE_FILE"


# --- Homebrew Installation (macOS only) ---

if [ "$DISTRO" == "macOS" ]; then
  if ! command_exists brew; then
    echo "Homebrew not found. Installing..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add brew to the current session's PATH
    if [ "$ARCH" == "arm64" ]; then # Apple Silicon
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else # Intel
        eval "$(/usr/local/bin/brew shellenv)"
    fi
  else
    echo "Homebrew is already installed."
  fi
fi

# --- Essential Build Dependencies ---

echo "Installing essential build dependencies..."
case "$DISTRO" in
  'ubuntu' | 'debian')
    sudo apt-get update
    sudo apt-get install -y build-essential curl file git unzip zlib1g-dev libbz2-dev liblzma-dev libssl-dev libsqlite3-dev libreadline-dev libffi-dev libncurses5-dev
    ;;
  'fedora' | 'centos' | 'rhel')
    sudo dnf groupinstall -y "Development Tools"
    sudo dnf install -y curl file git unzip zlib-devel bzip2-devel xz-devel openssl-devel sqlite-devel readline-devel ffi-devel ncurses-devel
    ;;
  'macOS')
    # On macOS, Xcode Command Line Tools are the equivalent.
    # They are often installed with Homebrew, but we can ensure they are present.
    if ! xcode-select -p &>/dev/null; then
        echo "Installing Xcode Command Line Tools..."
        xcode-select --install
    else
        echo "Xcode Command Line Tools are already installed."
    fi
    # brew install openssl readline sqlite3 xz zlib tcl-tk
    ;;
esac
echo "Build dependencies installed."


# --- HashiCorp Vault Installation ---

if ! command_exists vault; then
    echo "Vault not found. Installing..."
    case "$DISTRO" in
      'ubuntu' | 'debian' | 'fedora' | 'centos' | 'rhel')
        VAULT_VERSION="1.17.1"
        VAULT_ARCH="amd64"
        if [ "$ARCH" == "arm64" ] || [ "$ARCH" == "aarch64" ]; then
            VAULT_ARCH="arm64"
        fi
        curl -fsSL "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_${VAULT_ARCH}.zip" -o "/tmp/vault.zip"
        unzip -d /tmp /tmp/vault.zip
        sudo mv /tmp/vault /usr/local/bin/
        rm /tmp/vault.zip
        ;;
      'macOS')
        brew tap hashicorp/tap
        brew install hashicorp/tap/vault
        ;;
    esac
else
    echo "Vault is already installed."
fi


# --- Kubernetes Tools ---

# Install kubectl
if ! command_exists kubectl; then
    echo "kubectl not found. Installing..."
    case "$DISTRO" in
      'ubuntu' | 'debian' | 'fedora' | 'centos' | 'rhel')
        KUBE_ARCH="amd64"
        if [ "$ARCH" == "arm64" ] || [ "$ARCH" == "aarch64" ]; then
            KUBE_ARCH="arm64"
        fi
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${KUBE_ARCH}/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
        
        # Install kubectl completion
        ZSH_COMPLETION_DIR="/usr/local/share/zsh/site-functions"
        sudo mkdir -p "$ZSH_COMPLETION_DIR"
        kubectl completion zsh | sudo tee "$ZSH_COMPLETION_DIR/_kubectl" > /dev/null
        ;;
      'macOS')
        brew install kubectl
        ;;
    esac
else
    echo "kubectl is already installed."
fi

# Install kubectx and kubens
if ! command_exists kubectx || ! command_exists kubens; then
    echo "kubectx or kubens not found. Installing..."
    case "$DISTRO" in
      'ubuntu' | 'debian' | 'fedora' | 'centos' | 'rhel')
        KUBECTX_VERSION="v0.9.5"
        KUBE_ARCH="x86_64"
        if [ "$ARCH" == "arm64" ] || [ "$ARCH" == "aarch64" ]; then
            KUBE_ARCH="arm64"
        fi
        
        # Download kubectx binary
        curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubectx_${KUBECTX_VERSION}_linux_${KUBE_ARCH}.tar.gz" -o "/tmp/kubectx.tar.gz"
        tar -xzf /tmp/kubectx.tar.gz -C /tmp kubectx
        sudo install -o root -g root -m 0755 /tmp/kubectx /usr/local/bin/kubectx

        # Download kubens script
        curl -fsSL "https://raw.githubusercontent.com/ahmetb/kubectx/${KUBECTX_VERSION}/kubens" -o "/tmp/kubens"
        sudo install -o root -g root -m 0755 /tmp/kubens /usr/local/bin/kubens
        
        # Install Zsh completion scripts
        ZSH_COMPLETION_DIR="/usr/local/share/zsh/site-functions"
        sudo mkdir -p "$ZSH_COMPLETION_DIR"
        curl -fsSL "https://raw.githubusercontent.com/ahmetb/kubectx/${KUBECTX_VERSION}/completion/_kubectx.zsh" -o "/tmp/_kubectx.zsh"
        curl -fsSL "https://raw.githubusercontent.com/ahmetb/kubectx/${KUBECTX_VERSION}/completion/_kubens.zsh" -o "/tmp/_kubens.zsh"
        sudo install -o root -g root -m 0644 /tmp/_kubectx.zsh "$ZSH_COMPLETION_DIR/_kubectx"
        sudo install -o root -g root -m 0644 /tmp/_kubens.zsh "$ZSH_COMPLETION_DIR/_kubens"

        # Cleanup
        rm /tmp/kubectx.tar.gz /tmp/kubectx /tmp/kubens /tmp/_kubectx.zsh /tmp/_kubens.zsh
        ;;
      'macOS')
        brew install kubectx
        ;;
    esac
else
    echo "kubectx and kubens are already installed."
fi


# --- Data Processing Tools ---

# Install jq
if ! command_exists jq; then
    echo "jq not found. Installing..."
    case "$DISTRO" in
      'ubuntu' | 'debian')
        sudo apt-get install -y jq
        ;;
      'fedora' | 'centos' | 'rhel')
        sudo dnf install -y jq
        ;;
      'macOS')
        brew install jq
        ;;
    esac
else
    echo "jq is already installed."
fi

# Install yq
if ! command_exists yq; then
    echo "yq not found. Installing..."
    case "$DISTRO" in
      'ubuntu' | 'debian' | 'fedora' | 'centos' | 'rhel')
        YQ_VERSION="v4.44.2"
        YQ_ARCH="amd64"
        if [ "$ARCH" == "arm64" ] || [ "$ARCH" == "aarch64" ]; then
            YQ_ARCH="arm64"
        fi
        curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${YQ_ARCH}" -o "/tmp/yq"
        sudo install -o root -g root -m 0755 /tmp/yq /usr/local/bin/yq
        rm /tmp/yq
        ;;
      'macOS')
        brew install yq
        ;;
    esac
else
    echo "yq is already installed."
fi


# --- Web Server Tools ---

# Install Caddy
if ! command_exists caddy; then
    echo "Caddy not found. Installing..."
    case "$DISTRO" in
      'ubuntu' | 'debian')
        sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
        sudo apt-get update
        sudo apt-get install -y caddy
        ;;
      'macOS')
        brew install caddy
        ;;
    esac
else
    echo "Caddy is already installed."
fi


# --- Go Environment Provisioning ---

GO_VERSION="1.22.2"
GO_INSTALL_DIR="$HOME/.local/go"
GO_BIN_PATH="$GO_INSTALL_DIR/bin"

if [ -d "$GO_INSTALL_DIR" ] && [ "$( ($GO_INSTALL_DIR/bin/go version | cut -d ' ' -f3) )" == "go$GO_VERSION" ]; then
    echo "Go version $GO_VERSION is already installed."
else
    echo "Installing Go version $GO_VERSION..."
    rm -rf "$GO_INSTALL_DIR"
    
    GO_ARCH="amd64"
    if [ "$ARCH" == "arm64" ] || [ "$ARCH" == "aarch64" ]; then
        GO_ARCH="arm64"
    fi
    
        curl -fsSL "https://golang.org/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -o "/tmp/go.tar.gz"
        mkdir -p "$HOME/.local"
        tar -C "$HOME/.local" -xzf "/tmp/go.tar.gz"
        rm "/tmp/go.tar.gz"    
    echo "Go installed successfully."
fi

add_line_to_file 'export PATH=$PATH:'"$GO_BIN_PATH" "$PROFILE_FILE"


# --- Node.js Version Management with NVM ---

export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
  echo "NVM not found. Installing..."
  bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash'
else
  echo "NVM is already installed."
fi

# Source NVM for the current script session
. "$NVM_DIR/nvm.sh"

# Idempotently add NVM sourcing to the profile
NVM_SOURCE_SNIPPET='export NVM_DIR="$HOME/.nvm"\n[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm'
add_line_to_file "$NVM_SOURCE_SNIPPET" "$PROFILE_FILE"


# Install latest LTS Node.js version
if ! nvm ls "lts/*" | grep -q "lts/*"; then
  echo "Installing latest LTS version of Node.js..."
  nvm install --lts
  nvm alias default 'lts/*'
else
  echo "Latest LTS version of Node.js is already installed."
fi


# --- Python Version Management with Pyenv ---

if [ ! -d "$HOME/.pyenv" ]; then
  echo "pyenv not found. Installing..."
  curl https://pyenv.run | bash
else
  echo "pyenv is already installed."
fi

# Add pyenv to PATH and initialize
PYENV_INIT_SNIPPET='export PYENV_ROOT="$HOME/.pyenv"\ncommand -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"\neval "$(pyenv init -)"'
add_line_to_file "$PYENV_INIT_SNIPPET" "$PROFILE_FILE"

# Load pyenv into the current script session
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"


PYTHON_VERSION="3.12.2"
if ! pyenv versions --bare | grep -q "^$PYTHON_VERSION$"; then
  echo "Installing Python $PYTHON_VERSION..."
  pyenv install "$PYTHON_VERSION"
else
  echo "Python $PYTHON_VERSION is already installed."
fi

if [ "$(pyenv global)" != "$PYTHON_VERSION" ]; then
  echo "Setting global Python version to $PYTHON_VERSION..."
  pyenv global "$PYTHON_VERSION"
else
  echo "Global Python version is already set to $PYTHON_VERSION."
fi


# --- AWS Command Line Interface (v2) Setup ---

add_line_to_file 'export PATH=$PATH:'"$HOME/.local/bin" "$PROFILE_FILE"
export PATH="$PATH:$HOME/.local/bin" # Add to current session's PATH

if ! command_exists aws; then
  echo "AWS CLI v2 not found. Installing..."
  INSTALL_DIR="$HOME/.local/aws-cli"
  BIN_DIR="$HOME/.local/bin"
  mkdir -p "$INSTALL_DIR" "$BIN_DIR"

  cd /tmp
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip -q awscliv2.zip
  ./aws/install --update -i "$INSTALL_DIR" -b "$BIN_DIR"
  rm -f awscliv2.zip
  rm -rf aws
  cd -
else
  echo "AWS CLI v2 is already installed."
fi


# --- Gemini CLI Installation ---

if ! command_exists gemini; then
    echo "Gemini CLI not found. Installing..."
    # Ensure nvm is sourced
    . "$NVM_DIR/nvm.sh"
    npm install -g @google/gemini-cli
else
    echo "Gemini CLI is already installed."
fi


# --- chezmoi Installation ---

if ! command_exists chezmoi; then
    echo "chezmoi not found. Installing..."
    case "$DISTRO" in
      'ubuntu' | 'debian' | 'fedora' | 'centos' | 'rhel')
        sudo snap install chezmoi --classic
        ;;
      'macOS')
        brew install chezmoi
        ;;
      *) # Fallback for other distros
        sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
        ;;
    esac
else
    echo "chezmoi is already installed."
fi


echo "Bootstrap script completed successfully."
echo "Prerequisite tools installed. Chezmoi initialization will be handled by the playbook."
