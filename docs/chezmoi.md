# chezmoi: usage, reconciliation, and not losing your changes

[chezmoi](https://www.chezmoi.io) manages the dotfiles in this repo. This guide
covers the mental model, everyday commands, how this repo wires chezmoi up, and
— most importantly — **how to avoid losing local edits** (and how to keep
history so you can recover them).

> **Read this first if you've edited a dotfile by hand.** In the default mode
> the playbook runs `chezmoi apply --force`, which makes your home-directory
> files match the repo and **discards** edits made directly to managed files.
> See [Don't lose your changes](#dont-lose-your-changes).

---

## Mental model

chezmoi has three states:

```
  source state            target state              destination
  (this repo's       →    (what chezmoi       →     (your actual
   dotfiles/ dir)         computes you want)         ~/ files)
```

- **Source** — the repo's `dotfiles/` directory. This is the source of truth.
  `chezmoi apply` makes your home directory match it.
- **Target** — what chezmoi computes from the source (after rendering templates,
  decrypting, etc.).
- **Destination** — the real files in your home directory (`~/.zshrc`, …).

chezmoi also keeps a small **persistent state** (a BoltDB under
`~/.cache/chezmoi`/state) recording the hash it last wrote, so it can tell when
a destination file was changed *outside* chezmoi. That state stores **hashes,
not contents** — it is *not* a backup and cannot restore an overwritten file.

### Source naming conventions

chezmoi maps source filenames to destination paths by prefix/suffix:

| Source name | Becomes | Meaning |
| --- | --- | --- |
| `dot_zshrc` | `~/.zshrc` | `dot_` → leading `.` |
| `private_dot_ssh/` | `~/.ssh/` (mode 0600) | `private_` → not world/group readable |
| `dot_gitconfig.tmpl` | `~/.gitconfig` | `.tmpl` → rendered as a template |
| `run_once_*.sh` | (executed) | scripts — see [Scripts](#scripts) |

What's managed here today: `.bash_profile`, `.zprofile`, `.zshrc`, `.npmrc`,
`.tmux.conf`, `.gitconfig` (template), plus `dot_config/`, `dot_docker/`,
`private_dot_ssh/`, and a `Library/` tree. See `chezmoi managed` for the live list.

---

## How this repo wires chezmoi

The `dotfiles` Ansible role (`roles/dotfiles/`) does the setup:

1. Installs chezmoi via Homebrew.
2. Renders `~/.config/chezmoi/chezmoi.toml` from `chezmoi.toml.j2`, which sets:
   - `sourceDir` → this repo's `dotfiles/` directory.
   - `[data]` → `name`, `email`, `github_user`, pulled from your Ansible vars
     (`group_vars/local.yml`). This is how identity stays single-sourced and
     feeds templates like `dot_gitconfig.tmpl`.
3. Runs `chezmoi apply` (forced or not, per `dotfiles_enforce`).

Because `sourceDir` points at the repo, **the chezmoi source dir _is_ this git
repo** — editing `dotfiles/dot_zshrc` here and editing the chezmoi source are
the same action.

### Enforcement mode (`dotfiles_enforce`)

| `dotfiles_enforce` | Apply command | Local edits to managed files |
| --- | --- | --- |
| `true` (default) | `chezmoi apply --force` | **Overwritten** — repo wins, silently. |
| `false` | `chezmoi apply --no-tty --keep-going` | **Preserved** — conflicting files left as-is; a `[WARNING]` lists them. |

Full rationale: [docs/decisions/0001-chezmoi-conflict-handling.md](decisions/0001-chezmoi-conflict-handling.md).

---

## Everyday commands

Run these from anywhere (chezmoi knows its source dir from the config):

| Command | What it does |
| --- | --- |
| `chezmoi status` | One line per file that differs. Col 2 = `M`/`A`/`D` means the destination changed outside chezmoi. Never prompts, never writes. |
| `chezmoi diff` | Show exactly what `apply` would change. **Run this before every apply.** |
| `chezmoi diff ~/.zshrc` | Diff a single file. |
| `chezmoi managed` | List every path chezmoi manages. |
| `chezmoi apply` | Make the destination match the source (prompts on conflicts). |
| `chezmoi apply --dry-run --verbose` | Preview an apply without writing. |
| `chezmoi cd` | Drop into the source dir (this repo's `dotfiles/`) in a subshell. |
| `chezmoi edit ~/.zshrc` | Edit the **source** of a file (the right way to change a dotfile). |
| `chezmoi cat ~/.zshrc` | Print the target state (post-template) without applying. |
| `chezmoi verify` | Exit non-zero if any destination differs from target. |

---

## The golden rule: edit the source, not the destination

> **Change `dotfiles/<file>` in this repo (or use `chezmoi edit`), never edit
> `~/<file>` directly.**

If you edit `~/.zshrc` directly, your change lives only in the destination. The
next forced apply overwrites it from the repo and it's gone — this is exactly
how the `alias` lines got lost. Keeping changes in the source means they're
version-controlled and survive every apply.

---

## Reconciliation workflows

### A) You changed a dotfile in your home dir and want to keep it

Pull the destination back into the source, then commit:

```sh
chezmoi add ~/.zshrc        # copy ~/.zshrc into dotfiles/dot_zshrc
chezmoi cd                  # -> into the repo's dotfiles/
git -C "$(git rev-parse --show-toplevel)" add -A
# review, then commit on a branch + PR (see CONTRIBUTING / repo workflow)
```

`chezmoi add` is also how you start managing a brand-new file. For a file that's
already managed, `chezmoi re-add` updates the source from the current
destination (handy after you've tweaked several managed files in place).

### B) You changed the repo and want it on this machine

```sh
chezmoi diff                # see what will change
chezmoi apply               # or re-run: ansible-playbook site.yml --tags dotfiles
```

### C) Source and destination have *both* changed (a real conflict)

1. `chezmoi diff ~/.zshrc` to see the divergence.
2. Decide who wins:
   - **Repo wins:** `chezmoi apply --force ~/.zshrc` (destroys local edit).
   - **Local wins:** `chezmoi add ~/.zshrc`, then commit the source.
   - **Merge both:** `chezmoi merge ~/.zshrc` opens your `$EDITOR`/merge tool on
     source vs destination so you can combine them, then commit.

---

## Don't lose your changes

chezmoi keeps **no backup** of destination files it overwrites. Protect yourself
with one or more of these:

1. **Always `chezmoi diff` before applying.** It shows precisely what would be
   lost. The playbook's pre-flight `chezmoi status` + `[WARNING]` is the
   automated version of this.

2. **Put real changes in the source and commit them.** The repo's git history is
   your durable history for *intended* config. (It only covers what you've
   `chezmoi add`-ed/committed — not ad-hoc destination edits.)

3. **Use `dotfiles_enforce: false`** on machines that carry intentional local
   tweaks, so apply preserves divergent files and warns instead of overwriting.

4. **Enable Time Machine** (or another whole-disk backup). On this machine it's
   currently *not configured* (`tmutil destinationinfo` → "No destinations
   configured"), so there is no system-level safety net today. This is the
   single biggest gap — fix it.

5. **Optional: back up before forcing.** A snippet you can run before a forced
   apply to snapshot anything that's about to be overwritten:

   ```sh
   # Save every managed file that differs, before `apply --force` clobbers it.
   # `chezmoi status` prints two status chars + a space, then the path, so
   # `cut -c4-` yields the path (robust even if it contains spaces).
   backup="$HOME/.local/state/chezmoi-backup/$(date +%Y%m%d-%H%M%S)"
   chezmoi status | cut -c4- | while read -r rel; do
     src="$HOME/$rel"
     [ -e "$src" ] || continue
     mkdir -p "$backup/$(dirname "$rel")"
     cp -p "$src" "$backup/$rel"
   done
   [ -d "$backup" ] && echo "Backed up changed dotfiles to $backup"
   ```

   (If you'd like this wired into the `dotfiles` role to run automatically before
   a forced apply, open an issue / ask — it's a small addition.)

---

## Per-machine local overrides

To keep personal, machine-specific tweaks **outside** chezmoi's control (so they
can never be overwritten), have the managed file source an unmanaged local file.
For zsh, add to the end of `dotfiles/dot_zshrc`:

```sh
# Machine-local overrides — not managed by chezmoi, never overwritten.
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
```

Then put per-machine aliases/exports in `~/.zshrc.local`. chezmoi manages the
shared `~/.zshrc`; your `~/.zshrc.local` is yours alone. (This is the standard
"shared base + local extension" pattern and would have saved the lost aliases.)

---

## Templates & data

Files ending in `.tmpl` are rendered with Go templates using the `[data]` block
from `chezmoi.toml` (set by the Ansible role from `group_vars/local.yml`). Example
from `dot_gitconfig.tmpl`:

```gotmpl
[user]
    name = {{ .name }}
    email = {{ .email }}
```

Inspect rendered output without applying: `chezmoi cat ~/.gitconfig`. Add data
keys by editing `roles/dotfiles/templates/chezmoi.toml.j2` (and the Ansible vars
behind them), not the generated `~/.config/chezmoi/chezmoi.toml`.

---

## Scripts

chezmoi can run scripts as part of `apply` based on their source filename:

| Prefix | Runs |
| --- | --- |
| `run_` | Every apply. |
| `run_once_` | Once ever (tracked by content hash). |
| `run_onchange_` | When the script's contents change. |
| `run_before_` / `run_after_` | Ordered before/after the rest of the apply. |

This repo currently uses **no** chezmoi run-scripts. (The only repo script is
`scripts/check_homebrew_retries.py`, a CI check unrelated to chezmoi.) To add
one, drop e.g. `run_onchange_install-packages.sh.tmpl` into `dotfiles/`.

---

## Quick safe-run checklist

```sh
chezmoi diff                 # 1. preview every change
chezmoi diff ~/.zshrc        # 2. eyeball anything you care about
# 3a. happy? apply:
chezmoi apply                #    (or: ansible-playbook site.yml --tags dotfiles)
# 3b. a managed file has local edits you want to keep?
chezmoi add <file> && commit #    pull them into the repo first
```

---

## Troubleshooting

- **`could not open a new TTY: open /dev/tty: device not configured`** — chezmoi
  hit a conflict and tried to prompt with no terminal (e.g. under Ansible). The
  role handles this via `dotfiles_enforce`; see
  [decision 0001](decisions/0001-chezmoi-conflict-handling.md).
- **`<file> has changed since chezmoi last wrote it`** — the destination was
  edited outside chezmoi. Decide who wins using
  [workflow C](#c-source-and-destination-have-both-changed-a-real-conflict).
- **A change to `dotfiles/` didn't take effect** — run `chezmoi diff` to confirm
  it's seen, then `chezmoi apply`. Remember templates (`.tmpl`) depend on the
  `[data]` block.
