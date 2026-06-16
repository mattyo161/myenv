# Testing bootstrap.sh with a UTM macOS VM

UTM is already installed by this playbook, so you can spin up a fresh macOS VM on your Apple Silicon Mac to test the full bootstrap end-to-end without touching your real machine.

## One-time setup: create the VM

1. Download a macOS IPSW restore image from [ipsw.me](https://ipsw.me) — pick the same macOS version as your host (currently 26.5.1) or one major version back to catch any version-specific issues.

2. Open UTM → **+** → **Virtualize** → **macOS 12+**.

3. Under **Boot Image**, point it at the downloaded IPSW.

4. Recommended specs:
   - **CPU:** 4 cores
   - **RAM:** 8 GB
   - **Storage:** 80 GB (Homebrew + casks + mise tools add up fast)

5. Complete the macOS setup assistant inside the VM. Use a simple password — you'll be typing it a lot at `--ask-become-pass` prompts.

6. **Take a snapshot** immediately after first login (before installing anything). UTM → right-click VM → **Manage Snapshots** → **Save**. Name it `clean-install`. This is your reset point.

## Running the bootstrap test

Inside the VM:

```bash
# Install git (needed to clone — CLT prompt will appear)
xcode-select --install

# Clone the repo
git clone https://github.com/mattyo161/myenv.git
cd myenv

# Copy and fill in your identity
cp group_vars/local.yml.example group_vars/local.yml
nano group_vars/local.yml   # use dummy values — this is a test VM

# Run it
./bootstrap.sh
```

Watch for failures. When you find one, fix it in the repo on your real machine, push, pull inside the VM, and re-run. Because bootstrap.sh is idempotent, you can re-run it without resetting the VM — already-installed items are skipped.

## Resetting for a clean run

If you want to test the very first-run experience again (e.g. after fixing a bug that only triggers on a blank machine):

UTM → right-click VM → **Manage Snapshots** → restore `clean-install`.

The VM reverts to factory state in seconds.

## Things that can't be tested in a VM

- **Touch ID / biometric sudo** — not available in VMs; sudo falls back to password, which is fine for our purposes.
- **Docker Desktop** — requires a VM-within-a-VM (nested virtualisation), which UTM doesn't support on Apple Silicon. Skip it with `--skip-tags` or just accept it'll fail in the VM.
- **VirtualBox** — same nested virtualisation problem; skip it.
- **System Extension / kernel extension casks** — anything that loads a kext (some VPN clients, etc.) may fail in a VM.

To skip the known VM-incompatible casks:

```bash
./bootstrap.sh --extra-vars "homebrew_casks_common={{ homebrew_casks_common | reject('search', 'docker-desktop|virtualbox') | list }}"
```

Or just let them fail and ignore those specific errors — everything else will still install.
