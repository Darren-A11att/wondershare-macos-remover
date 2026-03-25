# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-03-16

### Added
- Initial release
- Dynamic scanning for all Wondershare artifacts (processes, applications, system files, user files, root files)
- Multi-pattern application detection (Wondershare, Filmora, PDFelement, UniConverter, DemoCreator, EdrawMax, EdrawMind, Recoverit, Dr.Fone, MobileTrans, Anireel)
- Case-insensitive bundle ID matching for both `com.wondershare.*` and `com.Wondershare.*` variants
- 8-phase removal process with verification
- Protected file recovery for project files (WFP, EDDX, EMMX)
- Interactive REPL mode with numbered item list, toggle, select/deselect ranges and categories
- `scan` command for read-only system inspection
- `remove` command with confirmation prompt (type "REMOVE" to proceed)
- `--dry-run` mode to preview changes without deleting
- `--force` mode to skip confirmation prompt
- Detailed logging to ~/Desktop
- Colored terminal output with `--no-color` option
- Compatible with macOS bash 3.2 (no bash 4+ features required)
