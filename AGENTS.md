# Agent Guide for myenv

myenv provisions a fresh macOS (Apple Silicon) laptop into Matt's working
environment in one command: Ansible orchestrates Homebrew (casks, formulae,
fonts), mise (runtimes and dev CLIs), VS Code extensions, and chezmoi-managed
dotfiles. It is the source of truth for machine setup — including
`~/.claude/` content (skills, global CLAUDE.md).

House rules: see [docs/AI_GUIDE.md](docs/AI_GUIDE.md). This file holds only
what is specific to this repo.

## Commands

```shell
./bootstrap.sh                          # first run: prompts identity, installs, runs everything
ansible-playbook site.yml               # converge the current machine
ansible-playbook site.yml --tags dotfiles   # one area (see role tags in site.yml)
ansible-playbook site.yml --check --diff    # dry-run: what would change
chezmoi diff                            # dotfiles: pending changes vs ~
chezmoi apply                           # dotfiles: deploy from dotfiles/
```

## Map

- `site.yml` + `roles/` — the playbook and per-area roles (brew, mise,
  vscode, dotfiles, ...).
- `dotfiles/` — chezmoi source tree (`dot_zshrc` → `~/.zshrc`,
  `dot_claude/` → `~/.claude/`); **edit here, then `chezmoi apply`** — never
  edit deployed files in `~` directly or the next apply clobbers them.
- `group_vars/` — settings; `local.yml` holds identity and is git-ignored
  (`local.yml.example` is the template).
- `scripts/` — helper scripts (travel-mode lives here).
- `config-examples/`, `inventory.ini`, `requirements.yml` — ansible plumbing.

## Style

Ansible tasks are idempotent and named in plain English; prefer module
parameters over `shell:`; guard destructive steps with `creates:`/`when:`.
Dotfiles follow chezmoi naming (`dot_`, `private_`, templates as `.tmpl`).

## Boundaries

**Always:** `--check --diff` before a real playbook run when changing roles;
route dotfile changes through `dotfiles/` (chezmoi source), not `~`.

**Ask first:** running the full playbook (it mutates this machine — brew
installs, app configs); adding new casks/formulae; anything touching
credentials or `group_vars/local.yml` handling.

**Never:** commit `group_vars/local.yml`, tokens, or machine-private values;
hand-edit files chezmoi deploys (the source tree wins).

## Verification

`ansible-playbook site.yml --check --diff` must be idempotent after a change
(second run: zero changed tasks). For dotfiles, `chezmoi diff` empty after
apply. For `~/.claude` changes, open a new Claude Code session and confirm
the deployed rules/skills load.