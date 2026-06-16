#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — from a bare macOS machine to a fully provisioned laptop.
#
#   ./bootstrap.sh                      # install everything
#   ./bootstrap.sh --skip-tags personal # skip personal-only apps
#   ./bootstrap.sh --check --diff       # dry run
#
# Any arguments are passed straight through to ansible-playbook.
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }

# 1. Xcode Command Line Tools -------------------------------------------------
# Required before Homebrew. Trigger the GUI installer and block until it's
# actually present, so this script completes in a single run.
if ! xcode-select -p >/dev/null 2>&1; then
  log "Installing Xcode Command Line Tools — complete the dialog that appears..."
  xcode-select --install || true
  printf "Waiting for Command Line Tools to finish installing"
  until xcode-select -p >/dev/null 2>&1; do printf "."; sleep 10; done
  printf " done.\n"
fi

# 2. Homebrew -----------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  log "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

# 3. Ansible (bootstrap copy; mise manages its own later) ---------------------
if ! command -v ansible-playbook >/dev/null 2>&1; then
  log "Installing Ansible via Homebrew..."
  brew install ansible
fi

# 4. Required Ansible collections ---------------------------------------------
log "Installing Ansible Galaxy collections..."
ansible-galaxy collection install -r requirements.yml

# 5. Allow Homebrew pkg-based casks to run their installers without a TTY -----
# Homebrew spawns its own sudo for .pkg installers (basictex, vagrant, etc.)
# and that call has no terminal. A sudoers drop-in grants NOPASSWD for just
# the two commands Homebrew needs so those casks install unattended.
SUDOERS_FILE=/etc/sudoers.d/homebrew-casks
if [[ ! -f "$SUDOERS_FILE" ]]; then
  log "Configuring passwordless sudo for Homebrew pkg installers (one-time)..."
  printf '%%admin ALL=(root) SETENV: NOPASSWD: /usr/sbin/installer\n%%admin ALL=(root) SETENV: NOPASSWD: /bin/mkdir\n%%admin ALL=(root) SETENV: NOPASSWD: /bin/chmod\n' \
    | sudo tee "$SUDOERS_FILE" > /dev/null
  sudo chmod 440 "$SUDOERS_FILE"
fi

# 6. Run the playbook ---------------------------------------------------------
# -K (--ask-become-pass) lets the xcode role accept the Xcode license via sudo.
# You'll be asked for your macOS password once; just press Enter if not needed.
log "Running the playbook..."
ansible-playbook -i inventory.ini site.yml --ask-become-pass "$@"

log "Done. See README.md for manual post-install steps (auth, SSH keys, etc.)."
