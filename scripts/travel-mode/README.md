# travel-mode

Keep a MacBook awake — lid closed, on battery — and its internet connection
alive while you're on the move: driving off an iPhone Personal Hotspot, hopping
between coworking spaces, or letting a long job run from a bag.

```
travel-mode run       # foreground; Ctrl-C stops and reverts everything
travel-mode start     # background service (launchd; survives closing the terminal)
travel-mode stop      # stop the service and restore normal sleep
travel-mode status    # service / connectivity / sleep-override state
travel-mode logs      # tail the service log
```

## Why

macOS is aggressive about sleeping on battery, and hotspot connections idle out
or drop when you drive between cells. Either one silently kills long-running
work. travel-mode counters both with three simple mechanisms:

1. **Stay awake** — `caffeinate -ims` holds the system awake while the display
   still sleeps and locks normally (no `-d`), so the machine isn't sitting
   unlocked in your bag.
2. **Lid override** — `pmset -a disablesleep 1` keeps the machine running even
   with the lid closed on battery (normally clamshell mode requires external
   power + display). Always reverted on stop/exit.
3. **Connectivity monitor** — a ping every 30 seconds (which doubles as a
   hotspot keep-alive). If the internet drops, it walks your preferred SSID
   list in order and reconnects, falling back to a WiFi power-cycle that
   triggers macOS auto-join.

## Why it pairs well with Claude Code

Long-running Claude Code sessions are exactly the workload that sleep and
hotspot dropouts kill: an agent mid-task, a streaming API response, background
subagents, a big test suite. With travel-mode running:

- Sessions keep executing during a drive — the laptop never sleeps, and when
  the hotspot blips between cell towers the connection recovers without you
  touching the machine.
- API streams and MCP connections resume instead of dying with the network.
- You can close the lid, put the laptop in a bag, and arrive with the task
  finished.

## Simplicity

- **One file, zero dependencies** — plain bash over macOS built-ins
  (`caffeinate`, `pmset`, `networksetup`, `launchctl`, `ping`). Nothing to
  update, nothing to break.
- **No stored secrets** — reconnect joins networks already saved in your
  Keychain; the config file holds only SSID names.
- **Minimal privilege** — exactly one command needs root (`pmset -a
  disablesleep`), granted via a sudoers drop-in scoped to that command and
  nothing else. The monitor loop runs entirely as your user.
- **Self-cleaning** — `stop` (or Ctrl-C in `run`) restores lid-close sleep and
  kills the caffeinate hold; the LaunchAgent plist is created on `start` and
  removed on `stop`.

## Install

Enable the ansible extra and run the playbook:

```bash
mv roles/extras/tasks/disabled/84-travel-mode.yml roles/extras/tasks/enabled/
ansible-playbook site.yml --tags extras
```

That installs three things:

| What | Where | Why |
| --- | --- | --- |
| Symlink to this script | `/usr/local/bin/travel-mode` | On PATH; `git pull` updates it in place. |
| Sudoers drop-in | `/etc/sudoers.d/travel-mode` | Passwordless `pmset -a disablesleep 1\|0` (only), so `start`/`stop` work unattended. |
| Default config | `~/.config/travel-mode/config` | Seeded once; your edits are never overwritten. |

Manual fallback: symlink the script onto your PATH yourself and run
`travel-mode run` — it will prompt for sudo interactively instead.

## Configuration

`~/.config/travel-mode/config` is a shell fragment sourced by the script:

```bash
TRAVEL_MODE_WIFI_DEV=en0                 # WiFi interface (networksetup -listallhardwareports)
TRAVEL_MODE_NETWORKS=(                   # SSIDs to try, in priority order
  HomeWireless5G
  iPhone-MOU17
)
TRAVEL_MODE_INTERVAL=30                  # seconds between connectivity probes
```

All options are also listed in [docs/configuration.md](../../docs/configuration.md).

## Foreground vs service

- `travel-mode run` stays attached to the terminal — good for a quick drive;
  Ctrl-C tears everything down.
- `travel-mode start` bootstraps a per-user **LaunchAgent**
  (`local.travel-mode`). launchd supervises it: it survives closing the
  terminal and is restarted automatically if it ever crashes (`KeepAlive`).
  Output goes to `~/Library/Logs/travel-mode.log` (`travel-mode logs` tails it).

## The tools it uses

- **`caffeinate`** — Apple's utility for creating power-management assertions.
  `-i` prevents idle sleep, `-m` prevents disk sleep, `-s` keeps the system
  awake on AC/battery. Omitting `-d` lets the display sleep and lock normally.
- **`pmset`** — the power-management settings tool. `pmset -a disablesleep 1`
  is the only supported way to stay awake with the lid closed on battery; it
  changes a system-wide setting, which is why it (alone) requires root.
  `pmset -g` reads the current state.
- **`networksetup`** — CLI for Network preferences.
  `-setairportnetwork <dev> <ssid>` joins a saved network using its Keychain
  password; `-setairportpower <dev> on|off` power-cycles WiFi, which nudges
  macOS into auto-joining the highest-priority known network.
- **`launchctl` / launchd** — macOS's native service manager. `bootstrap
  gui/$UID` loads the agent into your login session, `bootout` unloads it,
  `print` inspects it. `KeepAlive` in the plist makes launchd restart the
  worker if it dies — the reason the service mode beats a backgrounded shell
  loop.
- **`ping`** — one packet to `1.1.1.1` with a 5-second cap is the reachability
  probe; the periodic traffic also keeps an iPhone hotspot from idling out.

## Security notes

The sudoers drop-in grants passwordless root for **exactly two fixed command
lines** — `/usr/bin/pmset -a disablesleep 1` and `... 0` — with no wildcards,
validated by `visudo` at install time. Everything else (the monitor loop,
network joins, caffeinate) runs unprivileged. See
[docs/decisions/0002-travel-mode-privileges.md](../../docs/decisions/0002-travel-mode-privileges.md)
for why this was chosen over a root LaunchDaemon.
