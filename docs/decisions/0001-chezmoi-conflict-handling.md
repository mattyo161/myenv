# 0001 — How chezmoi handles dotfiles changed outside chezmoi

**Status:** Accepted · **Date:** 2026-06-26 · **Area:** `roles/dotfiles`

## Context

The dotfiles role applies the repo's dotfiles with `chezmoi apply`. When a
managed file has been edited *outside* chezmoi (e.g. an app rewrites
`~/.config/zed/settings.json`, or you tweak a file by hand), chezmoi treats it
as a conflict and, by default, **prompts** the user to decide whether to
overwrite it.

Ansible runs with no controlling terminal, so that prompt cannot be answered.
chezmoi tries to open `/dev/tty` and the play dies with:

```
chezmoi: .config/zed/settings.json: could not open a new TTY: open /dev/tty: device not configured
```

We needed the role to run unattended without crashing, while still respecting
that whether the repo or the local machine "wins" is a per-user choice — some
machines carry intentional local tweaks that should not be clobbered silently.

## Decision

1. **A `dotfiles_enforce` toggle (default `true`)** controls who wins:
   - `true` → `chezmoi apply --force`: the repo is the source of truth and
     conflicting files are overwritten silently.
   - `false` → `chezmoi apply --no-tty --keep-going`: `--no-tty` stops chezmoi
     from attempting to open `/dev/tty` (so it never crashes), and
     `--keep-going` applies every non-conflicting file while leaving the
     conflicting ones untouched, preserving local edits.

2. **Always probe first with `chezmoi status`.** `status` never prompts and
   never writes, so it is safe under Ansible. We parse its output for
   destination-side changes (column 2 = `M`/`A`/`D`) — exactly the files that
   would trigger the interactive prompt — and report them.

3. **Surface conflicts as real `[WARNING]`s.** A small notification callback
   plugin (`callback_plugins/warn_facts.py`) prints any `callback_warnings`
   fact through Ansible's warning channel, so conflicts show up highlighted and
   in the run summary instead of as ordinary `debug` output — in **both** modes,
   so you always learn which files diverged.

## Alternatives considered

- **`chezmoi apply --force` unconditionally.** Simplest, and it fixes the
  crash, but it silently destroys intentional local changes and gives the
  operator no say. Rejected as the *only* behavior; kept as the default.
- **Plain `chezmoi apply` with `failed_when: false`.** Still attempts to open
  `/dev/tty`, so it emits the scary error and aborts at the first conflict
  before applying the rest. `--no-tty --keep-going` is strictly better.
- **`ansible.builtin.debug` for the warning.** Works, but prints as normal task
  output, not a real warning, and never appears in the run's warning summary.
  The callback plugin gives a genuine `[WARNING]`.
- **A custom module calling `module.warn()`.** Also yields a real warning, but
  adds a module per call site; the callback is a single reusable plugin that any
  task can feed via a fact.

## Consequences

- The role runs unattended without a TTY in either mode.
- Operators get a clear, highlighted list of files that diverged from the repo.
- `callback_plugins/warn_facts.py` is enabled globally (`callbacks_enabled`),
  but it is inert for any task that does not set `callback_warnings`.
- In `dotfiles_enforce: false`, chezmoi stops short on conflicting files only;
  unrelated updates still apply. Flip the toggle per host/user via inventory,
  `group_vars`, or `host_vars`.
