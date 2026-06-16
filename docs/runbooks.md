# Runbooks

Common errors and how to fix them.

---

## `brew update` fails with "Host key verification failed"

**Symptom**

```
==> Updating Homebrew...
Host key verification failed.
fatal: Could not read from remote repository.
Error: Fetching /opt/homebrew failed!
```

**Cause**

`~/.gitconfig` contains a `[url]` rewrite that redirects all `https://github.com/`
URLs to `git@github.com:` (SSH). This is intentional — it means every `git clone`
or `git fetch` to GitHub uses your SSH key automatically. But on a fresh machine
where no SSH key has been added to GitHub yet, the rewrite causes Homebrew's
internal `git fetch` to fail with an authentication error.

**Fix — set `HOMEBREW_BREW_GIT_REMOTE` to bypass the rewrite**

This tells Homebrew to use a specific remote URL, bypassing the global git rewrite.
Add it to your shell config so it persists:

```bash
echo 'export HOMEBREW_BREW_GIT_REMOTE="https://github.com/Homebrew/brew.git"' >> ~/.zshrc
source ~/.zshrc
brew update
```

This keeps the SSH rewrite intact for all your own GitHub work. Once you add an
SSH key to your GitHub account the `HOMEBREW_BREW_GIT_REMOTE` export is still
harmless — Homebrew simply uses the URL you gave it rather than the rewritten one.

**Why not just remove the `insteadOf` rewrite?**

The `[url]` rewrite in `~/.gitconfig` is there on purpose. Without it, tools that
hard-code `https://` URLs (npm, various CLIs) would use HTTPS and prompt for a
password or token. The rewrite makes SSH the default silently. Removing it trades
that convenience for one fewer bootstrap gotcha.

**This is now handled automatically**

`dotfiles/dot_gitconfig.tmpl` wraps the `[url]` block in a chezmoi `stat` check
on `~/.ssh/id_ed25519`. When the key is absent the block is omitted, so
`brew update` works on a fresh machine. Once you add your SSH key, re-run chezmoi
(or the full playbook) and the rewrite will be included automatically:

```bash
chezmoi apply   # or: ansible-playbook -i inventory.ini site.yml --tags dotfiles
```

The manual fix above is only needed if you bootstrapped before this change was
in place.

---

## `docker-desktop` cask install fails with "sudo: a terminal is required"

**Symptom**

```
Error: Failure while executing; `/usr/bin/sudo -E -- /bin/ln -h -f -s -- \
  /Applications/Docker.app/Contents/Resources/bin/docker /usr/local/bin/docker` exited with 1.
sudo: a terminal is required to read the password
```

**Cause**

Homebrew needs `sudo` to create symlinks in `/usr/local/bin/` but there is no TTY
available when running under Ansible. The sudoers drop-in at
`/etc/sudoers.d/homebrew-casks` is either missing or does not include `/bin/ln`.

**Fix**

Re-run the playbook — the homebrew role adds the missing entry idempotently:

```bash
ansible-playbook -i inventory.ini site.yml --tags homebrew --ask-become-pass
```

Verify the entry was added:

```bash
sudo cat /etc/sudoers.d/homebrew-casks
```

Then retry:

```bash
brew install --cask docker-desktop
```
