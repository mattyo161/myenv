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

# 0. Prime sudo — ask for the password once upfront, then keep the timestamp
# alive in the background so it never expires mid-run (Homebrew, Ansible become,
# and the sudoers setup all need it at different points).
sudo -v
while true; do sudo -v; sleep 60; done &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT

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
  NONINTERACTIVE=1 brew install ansible
fi

# 4. Required Ansible collections ---------------------------------------------
log "Installing Ansible Galaxy collections..."
ansible-galaxy collection install -r requirements.yml

# 5. Run the playbook ---------------------------------------------------------
# -K (--ask-become-pass) is required for the xcode license step and for the
# homebrew role to write /etc/sudoers.d/homebrew-casks on the first run.
# You'll be asked for your macOS password once; just press Enter if not needed.
log "Running the playbook..."
ansible-playbook -i inventory.ini site.yml --ask-become-pass "$@"

log "Done. See README.md for manual post-install steps (auth, SSH keys, etc.)."
