# Wondershare macOS Remover

**Complete removal of Wondershare products and all related artifacts from macOS.**

Wondershare products auto-update past the version you paid for, then won't let you download the version your license covers. Their uninstallers leave behind gigabytes of launch daemons, caches, preferences, helper tools, and background processes. This tool finds and removes all of them.

## What It Does

- Dynamically scans your system for all Wondershare artifacts (processes, apps, caches, preferences, helpers)
- Kills all running Wondershare processes
- Unloads and removes launch agents and daemons
- Removes applications, frameworks, and helper tools
- Cleans system-level, user-level, and root-level files
- Removes Wondershare login items
- Verifies complete removal

## What It Preserves

Files with project extensions are **automatically recovered** to `~/Desktop/Wondershare-Recovered-Files/` before their parent directories are deleted:

| Product | Extension |
|---|---|
| Filmora | `.wfp` |
| EdrawMax | `.eddx` |
| EdrawMind | `.emmx` |

## Requirements

- macOS 11 (Big Sur) or later
- Administrator access (script must be run with `sudo`)
- Bash 3.2+ (included with macOS)

## Quick Start

```bash
# Download
git clone https://github.com/darrenallatt/wondershare-macos-remover.git
cd wondershare-macos-remover

# Make executable
chmod +x wondershare-remover.sh

# Launch interactive mode (recommended)
sudo ./wondershare-remover.sh
```

## Interactive Mode

Running without arguments launches the interactive REPL. It scans your system, presents a numbered list of all Wondershare artifacts, and lets you selectively toggle items before removal.

```
$ sudo ./wondershare-remover.sh

Wondershare macOS Remover v1.0.0
Scanning for Wondershare artifacts...

  ━━━ Running Processes (2) ━━━
   [x]  1. PID 1234 Wondershare Helper Compact
   [x]  2. PID 5678 WsHelper

  ━━━ Applications (2) ━━━
   [x]  3. Wondershare UniConverter 17.app       (1.8 GB)
   [x]  4. Wondershare PDFelement.app            (512 MB)

  ━━━ System Files (2) ━━━
   [x]  5. /Library/Application Support/Wondershare    (245 MB)
   [x]  6. /Library/Preferences/com.wondershare.PDFelement.plist

  Selected: 6/6 items (2.5 GB)

  Commands: all | none | N | select N-M | list | remove | help | quit

wondershare>
```

### REPL Commands

| Command | Action |
|---|---|
| `N` (bare number) | Toggle item N on/off |
| `all` | Select all items |
| `none` | Deselect all items |
| `select N` or `select N-M` | Select item or range |
| `deselect N` or `deselect N-M` | Deselect item or range |
| `select apps` | Select entire category (`proc`, `apps`, `agents`, `sys`, `user`, `root`) |
| `deselect apps` | Deselect entire category |
| `list` | Redisplay item list |
| `rescan` | Re-scan system (resets selections) |
| `remove` | Remove selected items (with confirmation) |
| `dry-run` | Preview removal without deleting |
| `help` | Show command reference |
| `quit` / `q` | Exit |

## CLI Mode

You can also use traditional CLI commands for scripting and automation.

```
sudo ./wondershare-remover.sh <command> [options]

Commands:
    (none)      Launch interactive mode (recommended)
    scan        Scan and report all Wondershare artifacts (read-only)
    remove      Scan, confirm, then remove everything
    help        Show help
    version     Show version

Options:
    --force         Skip confirmation prompt
    --dry-run       Show what would be removed (with 'remove')
    --no-color      Disable colored output
    --log-dir DIR   Custom log directory (default: ~/Desktop)
```

### Examples

```bash
# Interactive mode (recommended)
sudo ./wondershare-remover.sh

# See what's on your system (no changes made)
sudo ./wondershare-remover.sh scan

# Preview what would be removed
sudo ./wondershare-remover.sh remove --dry-run

# Remove with confirmation prompt
sudo ./wondershare-remover.sh remove

# Remove without confirmation (CI/automation)
sudo ./wondershare-remover.sh remove --force

# Custom log location
sudo ./wondershare-remover.sh remove --log-dir /tmp
```

## How It Works

The removal process runs in 8 phases:

| Phase | Action | Details |
|---|---|---|
| 1 | **Stop Processes** | SIGTERM, wait 3s, SIGKILL survivors |
| 2 | **Unload Launch Agents** | `launchctl bootout` / `remove` for all `com.wondershare.*` plists |
| 3 | **Remove Applications** | All apps matching Wondershare product names or `com.wondershare.*` bundle ID |
| 4 | **Remove System Files** | `/Library/Application Support/Wondershare`, frameworks, helper tools, preferences |
| 5 | **Remove User Files** | `~/Library/{Caches,Preferences,Logs,Containers,...}/com.wondershare.*` |
| 6 | **Remove Root/Temp Files** | `/private/var/root/Library/*wondershare*`, `/private/var/folders/*wondershare*` |
| 7 | **System Cleanup** | Refresh `cfprefsd`, remove login items |
| 8 | **Verify** | Re-scan to confirm complete removal |

### Confirmation

The `remove` command requires you to type `REMOVE` (not just Y/N) to proceed. This prevents accidental deletion. Use `--force` to skip this in automated environments.

### Logging

Every removal operation creates a detailed log file on your Desktop:
```
~/Desktop/wondershare-removal-20260316-143022.log
```

## Troubleshooting

### Some files remain after removal
Files protected by macOS System Integrity Protection (SIP) cannot be removed without disabling SIP. These are rare and generally harmless.

### "Operation not permitted" errors
Ensure your terminal app has **Full Disk Access** in System Settings > Privacy & Security > Full Disk Access.

### Login items persist
If Wondershare login items reappear, check System Settings > General > Login Items and remove them manually.

## Disclaimer

This tool is provided as-is. Always back up important files before running removal tools. The author is not responsible for any data loss. The tool includes file recovery for project files, but you should not rely on this as your only backup.

## License

[MIT](LICENSE)
