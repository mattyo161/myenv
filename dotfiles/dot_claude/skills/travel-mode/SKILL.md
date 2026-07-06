---
name: travel-mode
description: Control travel-mode (keeps the MacBook awake with the lid closed and auto-recovers internet across preferred WiFi networks/hotspots). Use when the user wants to start/stop/restart travel mode, check its status or logs, prep the laptop for a drive or working off a hotspot, or asks why the machine slept / lost network on the move. Managed in the myenv repo (scripts/travel-mode/).
---

# travel-mode control

`travel-mode` is a CLI installed at `/usr/local/bin/travel-mode` (symlinked into the
myenv repo). Background mode is a launchd LaunchAgent (`local.travel-mode`) — that's
the mode to use from Claude; never run `travel-mode run` (it blocks the shell holding
a foreground worker).

## Commands

```bash
travel-mode status    # service loaded? internet online? SleepDisabled state? network list
travel-mode start     # start the LaunchAgent (passwordless sudo via sudoers drop-in)
travel-mode stop      # stop it and restore normal lid-close sleep (waits for teardown)
```

- **Restart** = `travel-mode stop && travel-mode start`.
- **Logs**: don't use `travel-mode logs` (blocking `tail -f`). Instead:
  `tail -20 ~/Library/Logs/travel-mode.log`
- Config (SSID priority list, WiFi device, probe interval):
  `~/.config/travel-mode/config` — shell fragment, safe to edit; takes effect on
  next start. WiFi passwords are never stored there (Keychain handles them).

## Verifying

After `start`, confirm all three (they are what "working" means):

```bash
travel-mode status                        # service: running + internet: online
pmset -g | grep SleepDisabled             # 1 = lid-close sleep overridden
pgrep -lf "travel-mode _worker"           # worker process alive (launchd restarts it)
```

After `stop`, `SleepDisabled` must be back to `0` — if not, run
`sudo -n /usr/bin/pmset -a disablesleep 0`.

## Troubleshooting

- **`travel-mode: command not found`** — the ansible extra isn't applied on this
  machine. Enable it from the myenv repo:
  `mv roles/extras/tasks/disabled/84-travel-mode.yml roles/extras/tasks/enabled/`
  then `ansible-playbook site.yml --tags extras` (needs `--ask-become-pass`; suggest
  the user run it with a `!` prefix so it can prompt).
- **"could not set disablesleep" warning** — the sudoers drop-in
  (`/etc/sudoers.d/travel-mode`) is missing; re-run the ansible extra as above.
  Everything else still works; only the lid-close override is skipped.
- **Online but reconnect never fires** — the worker only walks the network list
  when a ping to 1.1.1.1 fails; check the log for `internet down — trying <ssid>`
  lines to see recovery in action.
- **Machine-wide caveat**: `pmset disablesleep 1` persists across a crash. If the
  laptop was hard-reset while travel-mode was active, run `travel-mode stop` once to
  clean up.

Full docs: `scripts/travel-mode/README.md` in the myenv repo; design trade-offs in
`docs/decisions/0002-travel-mode-privileges.md`.
