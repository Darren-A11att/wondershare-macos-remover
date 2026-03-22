# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-03-16

### Added
- Initial release
- Interactive REPL mode — launched by running without arguments (`sudo ./wondershare-remover.sh`)
- Numbered item list with `[x]`/`[ ]` checkboxes grouped by category
- Toggle individual items by number, select/deselect ranges (`select 3-6`), or entire categories (`select apps`)
- `all`/`none` for bulk selection, `list` to redisplay, `rescan` to re-scan
- `dry-run` command in REPL to preview removal without deleting
- Selection summary showing count and estimated size of selected items
- Dynamic scanning for all Wondershare artifacts (processes, applications, system files, user files, root files)
- Multi-pattern application scanning (Wondershare, Filmora, PDFelement, UniConverter, etc.)
- Case-insensitive bundle ID matching for `com.wondershare.*` / `com.Wondershare.*`
- 8-phase removal process with verification
- Protected file recovery for project files (WFP, EDDX, EMMX)
- `scan` command for read-only system inspection
- `remove` command with confirmation prompt (type "REMOVE" to proceed)
- `--dry-run` mode to preview changes without deleting
- `--force` mode to skip confirmation prompt
- Detailed logging to ~/Desktop
- Colored terminal output with `--no-color` option
- Compatible with macOS bash 3.2 (no bash 4+ features required)
