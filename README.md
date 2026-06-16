# myenv — Repeatable macOS Laptop Setup

Provision a fresh macOS (Apple Silicon) laptop with the same apps, dev tools, and
configuration in one command. Orchestrated by **Ansible**, with:

- **Homebrew** — GUI apps (casks), CLI formulae, fonts, taps
- **mise** — language runtimes & dev CLIs
- **VS Code** — editor extensions
- **chezmoi** — dotfiles, templated per user

## Before you run (required first step)

The repo ships with **placeholder identity values**. You must replace them with your own in
`group_vars/personal.yml` before running — the playbook **refuses to start** while the
placeholders are still in place (a pre-flight assert aborts before anything is installed)

Optionally review the rest of `group_vars/all.yml` (package/cask/mise lists) and trim
anything you don't want.

## Quickstart

```bash
git clone <this-repo-url> myenv
cd myenv

# 1. REQUIRED: set your identity (see "Before you run" above)
cp group_vars/local.yml.example group_vars/local.yml
$EDITOR group_vars/local.yml

# 2. Run it
./bootstrap.sh
```

`bootstrap.sh` installs the Xcode Command Line Tools, Homebrew, and Ansible, then runs the
playbook. It is **idempotent** — safe to run repeatedly. If you forget step 1, it stops
immediately with a message telling you to edit `group_vars/all.yml`.

## Useful installs if not part of bootstrap

### claude code cli
```bash
curl -fsSL https://claude.ai/install.sh | bash
```

## Trust Homebrew taps

Non-official taps must be trusted before Homebrew will load their formulae/casks
when `HOMEBREW_REQUIRE_TAP_TRUST` is set. The `homebrew` role does this
automatically: every tap listed in `homebrew_taps` is trusted via
`brew trust --tap` right after it is added, so anything you add there is covered
without a manual step. Trusting a tap trusts all of its formulae and casks.

The taps trusted by default (from `group_vars/all.yml`):

```bash
brew trust --tap cloudgraphdev/tap   # CloudGraph CLI — manage cloud accounts via GraphQL
brew trust --tap siderolabs/tap      # siderolabs — Talos, the Kubernetes OS
brew trust --tap supabase/tap        # supabase — cloud-native/scale PostgreSQL
```

TODO: make these optional selections — if a service/CLI isn't installed, don't try
to install it; if it is marked for install, ensure its tap is added and trusted.

## Sudoers drop-in for Homebrew casks

Some casks ship as `.pkg` installers (basictex, vagrant, virtualbox) or need to create
system directories (docker-desktop creates `/usr/local/bin`). Homebrew runs these steps by
spawning its own `sudo` call internally — not through Ansible — and that call has no
terminal attached, so sudo can't prompt for a password.

`bootstrap.sh` creates `/etc/sudoers.d/homebrew-casks` on first run to grant three specific commands passwordless access:

```
%admin ALL=(root) SETENV: NOPASSWD: /usr/sbin/installer
%admin ALL=(root) SETENV: NOPASSWD: /bin/mkdir
%admin ALL=(root) SETENV: NOPASSWD: /bin/chmod
```

- **`NOPASSWD`** — skips the interactive password prompt for these commands only.
- **`SETENV`** — allows Homebrew to pass `-E` (preserve environment) to sudo, which it uses to forward variables like `LOGNAME` and `USERNAME` into the installer context. Without `SETENV`, sudo rejects the `-E` flag with *"sorry, you are not allowed to preserve the environment"*.

The rules are scoped to the three commands Homebrew actually needs — not a blanket `NOPASSWD: ALL`. `/usr/sbin/installer` runs `.pkg` installers (basictex, vagrant, virtualbox), `/bin/mkdir` creates system directories (docker-desktop needs `/usr/local/bin`), and `/bin/chmod` fixes permissions on files installed into system paths (vagrant completion scripts).

## Common commands

```bash
./bootstrap.sh                       # everything
./bootstrap.sh --skip-tags personal  # skip personal-only apps (Chrome, Logseq, Obsidian)
./bootstrap.sh --check --diff        # dry run, show what would change

# After bootstrap, the playbook can be re-run directly per layer:
ansible-playbook site.yml --tags homebrew
ansible-playbook site.yml --tags mise
ansible-playbook site.yml --tags vscode
ansible-playbook site.yml --tags dotfiles
```

## What goes where

| File | Purpose |
| --- | --- |
| `group_vars/all.yml` | **The one file you edit.** Identity + all package lists. |
| `site.yml` | Main playbook; wires up the roles and tags. |
| `roles/xcode` | Ensures the build toolchain: Command Line Tools, Xcode license accepted, first-launch components, verified compile. |
| `roles/homebrew` | Taps, formulae, common + personal casks. |
| `roles/mise` | Installs mise, writes `~/.config/mise/config.toml`, installs tools. |
| `roles/vscode` | Installs VS Code extensions via the `code` CLI. |
| `roles/extras` | Optional add-ons — opt in by moving files (see below). |
| `roles/dotfiles` | Installs chezmoi and applies the dotfiles. |
| `dotfiles/` | chezmoi source dir (`dot_zshrc` → `~/.zshrc`, etc.). |

### How identity stays in sync
chezmoi reads its template data (`name`, `email`, `github_user`) from a config file that the
`dotfiles` role renders from `group_vars/all.yml`. So editing that one vars file updates both
the apps and the dotfiles — no duplication.

### Captured app & editor configs
chezmoi also manages these (extracted from the reference machine, secrets excluded):

- **Editors:** VS Code & Cursor `settings.json` + Cursor `keybindings.json`
  (`~/Library/Application Support/{Code,Cursor}/User/`), Zed `~/.config/zed/settings.json`.
  Cursor settings were cleaned of machine-specific absolute paths and personal DB connections.
- **Shell/tools:** `~/.ssh/config` (1Password SSH agent), k9s `config.yaml`/`aliases.yaml`,
  `~/.docker/config.json`.
- **iTerm2:** binary prefs live in `roles/dotfiles/files/iterm2/`; the dotfiles role sets
  iTerm2's *"load preferences from custom folder"* to point there (`osx_defaults`).

**Not managed here:**
- `config-examples/aws-config.template` — anonymized AWS SSO/profile skeleton to copy to
  `~/.aws/config` and fill in with employer values (not auto-applied, so it can't clobber).
- `personal/` — git-ignored. Personal AWS org config and Cursor email/IMAP connections,
  kept off the work repo; apply by hand only if wanted. See `personal/README.md`.
- Secrets are never captured: argocd auth-token, gh/keyring auth, cloudgraph creds.

### Personal vs shared
Personal-only casks live in `homebrew_casks_personal` and are tagged `personal`. Colleagues
who don't want them run `--skip-tags personal`.

## Optional extras (opt-in by dragging a file)

Curated multi-cloud / platform add-ons live in `roles/extras/tasks/`:

- **`disabled/`** — available but **never run**.
- **`enabled/`** — anything here runs automatically on the next playbook run.

To turn one on, move its file from `disabled/` → `enabled/` and re-run
(`./bootstrap.sh` or `ansible-playbook site.yml --tags extras`). To turn it off, move it back.

| File | Adds |
| --- | --- |
| `10-aws.yml` | eksctl, aws-vault, session-manager-plugin |
| `20-azure.yml` | kubelogin (AKS / Entra ID auth for kubectl) |
| `30-gcp.yml` | gke-gcloud-auth-plugin (GKE kubectl auth) |
| `40-kubernetes.yml` | kustomize, kubeseal, helmfile, krew |
| `50-iac.yml` | terragrunt, terraform-docs, tflint, checkov, infracost |
| `60-containers-security.yml` | trivy, dive, lazydocker |
| `70-local-k8s.yml` | starts a local k3s cluster via colima (`--kubernetes`) |
| `80-apps-core.yml` | iterm2, zed, 1password (+cli) — apps you already have configs for |
| `81-apps-infra.yml` | lens, raspberry-pi-imager, wireshark, charles, termius, mysqlworkbench, drawio |
| `82-apps-editors.yml` | cursor, github, intellij-idea-ce, pycharm-ce, bbedit, claude |
| `83-apps-productivity.yml` | firefox, teams, outlook, onedrive, zoom, discord, grammarly, vlc, gimp, balenaetcher |
| `90-mac-app-store.yml` | installs `mas` + App Store apps (Xcode, Things 3, iWork, …) — sign into the App Store first |

Each file is self-contained, so you can mix and match. Open one to see exactly what it installs
before enabling it.

## Manual post-install steps (secrets — intentionally not automated)

These require interactive login or private keys and are **not** handled by the playbook:

- `gh auth login` — GitHub CLI authentication
- Generate an SSH key and add it to GitHub. The included `.gitconfig` rewrites
  `https://github.com/` → `git@github.com:`, so GitHub access uses SSH.
- **Cloud logins (multi-cloud):**
  - AWS: `aws configure` (or `aws configure sso`)
  - Azure: `az login`
  - GCP: `gcloud init` (or `gcloud auth login` + `gcloud auth application-default login`)
- Sign into **1Password**, **Docker Desktop**, **Slack**
- Place your cluster credentials at `~/.kube/config` (referenced by `.zshrc`)
- Sign into Google Chrome

## Customizing / pinning versions

`mise_tools` in `group_vars/all.yml` uses `latest` to mirror the reference machine. For
stricter reproducibility across the team, pin exact versions there, e.g. `node: "20.19.2"`.
