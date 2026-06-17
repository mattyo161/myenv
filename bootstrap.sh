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
# -n (non-interactive) in the loop avoids printing a "Password:" prompt to the
# terminal while other programs are waiting for input.
log "Caching sudo credentials for the duration of the bootstrap run..."
sudo -v
while true; do sleep 50; sudo -n -v 2>/dev/null || true; done &
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

# 3. mise — single-binary tool manager ----------------------------------------
if [[ ! -x "$HOME/.local/bin/mise" ]]; then
  log "Installing mise..."
  curl -fsSL https://mise.run | sh
fi
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

# 4. Ansible (via mise/pipx — avoids brew pulling in a full Python@3.14 stack) -
# Version is read from group_vars/all.yml to stay in sync with the playbook.
# Install python then pipx first; mise uses pipx as the ansible backend and
# pipx requires Python 3.10+ which may not be present on a fresh macOS machine.
ANSIBLE_VERSION="$(awk '/^  ansible:/ {print $2}' group_vars/all.yml)"
if ! command -v ansible-playbook >/dev/null 2>&1; then
  log "Installing Ansible ${ANSIBLE_VERSION} via mise..."
  MISE_YES=1 mise use --global python@latest
  MISE_YES=1 mise use --global pipx@latest
  MISE_YES=1 mise use --global "ansible@${ANSIBLE_VERSION}"
fi

# 5. Required Ansible collections ---------------------------------------------
log "Installing Ansible Galaxy collections..."
ansible-galaxy collection install -r requirements.yml

# 6. Run the playbook ---------------------------------------------------------
# -K (--ask-become-pass) is required for the xcode license step and for the
# homebrew role to write /etc/sudoers.d/homebrew-casks on the first run.
# You'll be asked for your macOS password once; just press Enter if not needed.
log "Running the playbook..."
ansible-playbook -i inventory.ini site.yml --ask-become-pass "$@"

log "Done. See README.md for manual post-install steps (auth, SSH keys, etc.)."
