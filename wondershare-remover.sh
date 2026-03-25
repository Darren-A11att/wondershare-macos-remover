#!/bin/bash
# ============================================================================
# Wondershare macOS Remover v1.0.0
# Complete removal of Wondershare products and all related artifacts from macOS
#
# https://github.com/darrenallatt/wondershare-macos-remover
# License: MIT
# ============================================================================

set -uo pipefail

VERSION="1.0.0"

# =============================================================================
# Color Constants
# =============================================================================
if [[ "${NO_COLOR:-}" == "1" ]] || [[ "${TERM:-}" == "dumb" ]]; then
    RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" BOLD="" DIM="" RESET=""
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
fi

# =============================================================================
# Configuration
# =============================================================================

# Protected file extensions — user work files that must be preserved
PROTECTED_EXTENSIONS=(
    wfp       # Filmora project
    eddx      # EdrawMax
    emmx      # EdrawMind
)

# Process name patterns to kill
WONDERSHARE_PROCESS_PATTERNS=(
    "Wondershare"
    "Filmora"
    "PDFelement"
    "UniConverter"
    "DemoCreator"
    "EdrawMax"
    "EdrawMind"
    "Recoverit"
    "Dr.Fone"
    "MobileTrans"
    "Anireel"
    "WsHelper"
    "MediaDownloadKit"
)

# =============================================================================
# Global State
# =============================================================================
FOUND_PROCESSES=()
FOUND_APPLICATIONS=()
FOUND_LAUNCH_AGENTS=()
FOUND_SYSTEM_FILES=()
FOUND_USER_FILES=()
FOUND_ROOT_FILES=()
TOTAL_SIZE=0
DRY_RUN=0
FORCE=0
LOG_DIR=""
LOG_FILE=""
REAL_USER=""
REAL_HOME=""
RECOVERY_DIR=""
SUDO_KEEPALIVE_PID=""

# Interactive REPL state (parallel arrays)
ITEM_PATHS=()
ITEM_CATEGORIES=()
ITEM_SELECTED=()
ITEM_LABELS=()
ITEM_SIZES=()
REPL_FIRST_TOGGLE=1

# =============================================================================
# Logging Functions
# =============================================================================

_log() {
    local color="$1" prefix="$2" msg="$3"
    printf "${color}${BOLD}[%s]${RESET} %s\n" "$prefix" "$msg"
    if [[ -n "$LOG_FILE" ]] && [[ -w "$(dirname "$LOG_FILE")" || -w "$LOG_FILE" ]]; then
        printf "[%s] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$prefix" "$msg" >> "$LOG_FILE" 2>/dev/null
    fi
}

info()    { _log "$BLUE"    "INFO"    "$1"; }
warn()    { _log "$YELLOW"  "WARN"    "$1"; }
error()   { _log "$RED"     "ERROR"   "$1"; }
success() { _log "$GREEN"   "OK"      "$1"; }

header() {
    local msg="$1"
    local line
    line=$(printf '=%.0s' $(seq 1 ${#msg}))
    printf "\n${MAGENTA}${BOLD}%s${RESET}\n" "$msg"
    printf "${DIM}%s${RESET}\n\n" "$line"
    if [[ -n "$LOG_FILE" ]]; then
        printf "\n[%s] === %s ===\n\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$msg" >> "$LOG_FILE" 2>/dev/null
    fi
}

# =============================================================================
# Utility Functions
# =============================================================================

get_real_user() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        REAL_USER="$SUDO_USER"
    else
        REAL_USER="$(whoami)"
    fi
    REAL_HOME="/Users/$REAL_USER"
    RECOVERY_DIR="$REAL_HOME/Desktop/Wondershare-Recovered-Files"
}

require_sudo() {
    if [[ $EUID -ne 0 ]]; then
        error "This command must be run with sudo."
        echo ""
        echo "  Usage: sudo $0 $*"
        echo ""
        exit 1
    fi
    # Background sudo keep-alive
    (
        while true; do
            sudo -n true 2>/dev/null
            sleep 50
        done
    ) &
    SUDO_KEEPALIVE_PID=$!
}

cleanup_sudo_keepalive() {
    if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null
    fi
}

bytes_to_human() {
    local bytes="${1:-0}"
    if [[ "$bytes" -ge 1073741824 ]]; then
        printf "%.1f GB" "$(echo "scale=1; $bytes / 1073741824" | bc 2>/dev/null || echo 0)"
    elif [[ "$bytes" -ge 1048576 ]]; then
        printf "%.1f MB" "$(echo "scale=1; $bytes / 1048576" | bc 2>/dev/null || echo 0)"
    elif [[ "$bytes" -ge 1024 ]]; then
        printf "%.1f KB" "$(echo "scale=1; $bytes / 1024" | bc 2>/dev/null || echo 0)"
    else
        printf "%d bytes" "$bytes"
    fi
}

dir_size_bytes() {
    local path="$1"
    if [[ -e "$path" ]]; then
        du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}'
    else
        echo 0
    fi
}

confirm_action() {
    local item_count="$1"
    local total_size_human
    total_size_human="$(bytes_to_human "$TOTAL_SIZE")"

    printf "\n${RED}${BOLD}╔══════════════════════════════════════════════════╗${RESET}\n"
    printf "${RED}${BOLD}║          ⚠️  DESTRUCTIVE OPERATION  ⚠️            ║${RESET}\n"
    printf "${RED}${BOLD}╚══════════════════════════════════════════════════╝${RESET}\n\n"
    printf "  Items to remove:  ${BOLD}%d${RESET}\n" "$item_count"
    printf "  Estimated size:   ${BOLD}%s${RESET}\n" "$total_size_human"
    printf "  Recovery folder:  ${BOLD}%s${RESET}\n\n" "$RECOVERY_DIR"
    printf "  ${YELLOW}Protected files (WFP, EDDX, EMMX) will be copied${RESET}\n"
    printf "  ${YELLOW}to the recovery folder before removal.${RESET}\n\n"
    printf "  Type ${RED}${BOLD}REMOVE${RESET} to proceed, anything else to cancel: "

    local response
    read -r response
    if [[ "$response" != "REMOVE" ]]; then
        info "Operation cancelled by user."
        cleanup_sudo_keepalive
        exit 0
    fi
    echo ""
}

is_protected_extension() {
    local file="$1"
    local ext="${file##*.}"
    ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
    local protected
    for protected in "${PROTECTED_EXTENSIONS[@]}"; do
        if [[ "$ext" == "$protected" ]]; then
            return 0
        fi
    done
    return 1
}

recover_protected_files() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        return
    fi
    # Search for protected files in this directory
    local found_any=0
    while IFS= read -r -d '' file; do
        if is_protected_extension "$file"; then
            if [[ $found_any -eq 0 ]]; then
                mkdir -p "$RECOVERY_DIR"
                found_any=1
            fi
            local relpath="${file#/}"
            local dest="$RECOVERY_DIR/$relpath"
            mkdir -p "$(dirname "$dest")"
            if cp -a "$file" "$dest" 2>/dev/null; then
                success "Recovered: $file → $dest"
            else
                warn "Failed to recover: $file"
            fi
        fi
    done < <(find "$dir" -type f -print0 2>/dev/null)
}

safe_remove() {
    local path="$1"
    local label="${2:-$path}"

    if [[ ! -e "$path" ]] && [[ ! -L "$path" ]]; then
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY RUN] Would remove: $label"
        return 0
    fi

    # Recover protected files from directories (skip /Applications)
    if [[ -d "$path" ]] && [[ "$path" != /Applications/* ]]; then
        recover_protected_files "$path"
    fi

    if rm -rf "$path" 2>/dev/null; then
        success "Removed: $label"
        return 0
    else
        warn "Failed to remove: $label (may be SIP-protected)"
        return 1
    fi
}

create_log_file() {
    local timestamp
    timestamp="$(date '+%Y%m%d-%H%M%S')"
    if [[ -z "$LOG_DIR" ]]; then
        LOG_DIR="$REAL_HOME/Desktop"
    fi
    mkdir -p "$LOG_DIR" 2>/dev/null
    LOG_FILE="$LOG_DIR/wondershare-removal-${timestamp}.log"
    touch "$LOG_FILE" 2>/dev/null
    if [[ -f "$LOG_FILE" ]]; then
        chown "$REAL_USER" "$LOG_FILE" 2>/dev/null
        info "Log file: $LOG_FILE"
    else
        warn "Could not create log file at $LOG_FILE"
        LOG_FILE=""
    fi
}

# =============================================================================
# Scanner Functions (Read-Only)
# =============================================================================

scan_processes() {
    FOUND_PROCESSES=()
    local pattern
    for pattern in "${WONDERSHARE_PROCESS_PATTERNS[@]}"; do
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                FOUND_PROCESSES+=("$line")
            fi
        done < <(pgrep -fil "$pattern" 2>/dev/null | grep -iv "wondershare-remover" || true)
    done
    # Deduplicate
    if [[ ${#FOUND_PROCESSES[@]} -gt 0 ]]; then
        local unique=()
        local seen=""
        local proc
        for proc in "${FOUND_PROCESSES[@]}"; do
            local pid
            pid="$(echo "$proc" | awk '{print $1}')"
            if [[ "$seen" != *"|$pid|"* ]]; then
                unique+=("$proc")
                seen="${seen}|${pid}|"
            fi
        done
        FOUND_PROCESSES=("${unique[@]}")
    fi
}

scan_applications() {
    FOUND_APPLICATIONS=()

    # Wondershare products don't always include "Wondershare" in the name,
    # so we need multiple search patterns
    local app_name_patterns=(
        "*Wondershare*"
        "*Filmora*"
        "*PDFelement*"
        "*UniConverter*"
        "*DemoCreator*"
        "*EdrawMax*"
        "*EdrawMind*"
        "*Recoverit*"
        "*Dr.Fone*"
        "*MobileTrans*"
        "*Anireel*"
    )

    # Find by name patterns (with deduplication)
    local seen_apps=""
    local pat
    for pat in "${app_name_patterns[@]}"; do
        while IFS= read -r app; do
            if [[ -n "$app" ]] && [[ "$seen_apps" != *"|$app|"* ]]; then
                FOUND_APPLICATIONS+=("$app")
                seen_apps="${seen_apps}|${app}|"
            fi
        done < <(find /Applications -maxdepth 2 -iname "$pat" -type d 2>/dev/null || true)
    done

    # Also check all .app bundles for com.wondershare bundle IDs (case-insensitive)
    while IFS= read -r app; do
        if [[ -n "$app" ]] && [[ -f "$app/Contents/Info.plist" ]]; then
            local bid
            bid="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist" 2>/dev/null || true)"
            local bid_lower
            bid_lower="$(echo "$bid" | tr '[:upper:]' '[:lower:]')"
            if [[ "$bid_lower" == com.wondershare.* ]]; then
                # Check not already in list
                if [[ "$seen_apps" != *"|$app|"* ]]; then
                    FOUND_APPLICATIONS+=("$app")
                    seen_apps="${seen_apps}|${app}|"
                fi
            fi
        fi
    done < <(find /Applications -maxdepth 2 -name "*.app" -type d 2>/dev/null || true)

    # Add size estimates
    local app
    for app in "${FOUND_APPLICATIONS[@]+"${FOUND_APPLICATIONS[@]}"}"; do
        local size
        size="$(dir_size_bytes "$app")"
        TOTAL_SIZE=$((TOTAL_SIZE + size))
    done
}

scan_launch_agents() {
    FOUND_LAUNCH_AGENTS=()
    local search_dirs=(
        "/Library/LaunchAgents"
        "/Library/LaunchDaemons"
        "$REAL_HOME/Library/LaunchAgents"
    )
    local dir
    for dir in "${search_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            while IFS= read -r plist; do
                if [[ -n "$plist" ]]; then
                    FOUND_LAUNCH_AGENTS+=("$plist")
                fi
            done < <(find "$dir" -iname "com.wondershare.*" -type f 2>/dev/null || true)
        fi
    done
}

scan_system_files() {
    FOUND_SYSTEM_FILES=()
    local patterns=(
        "/Library/Application Support:Wondershare"
        "/Library/Application Support:MediaDownloadKit"
        "/Library/Preferences:com.wondershare.*"
        "/Library/Preferences:com.Wondershare.*"
        "/Library/PrivilegedHelperTools:com.wondershare.*"
        "/Library/PrivilegedHelperTools:com.Wondershare.*"
        "/Library/Frameworks:Wondershare*"
    )
    local pat
    for pat in "${patterns[@]}"; do
        local dir_part="${pat%%:*}"
        local base_part="${pat##*:}"
        if [[ -d "$dir_part" ]]; then
            while IFS= read -r match; do
                if [[ -n "$match" ]]; then
                    FOUND_SYSTEM_FILES+=("$match")
                    local size
                    size="$(dir_size_bytes "$match")"
                    TOTAL_SIZE=$((TOTAL_SIZE + size))
                fi
            done < <(find "$dir_part" -maxdepth 1 -iname "$base_part" 2>/dev/null || true)
        fi
    done
}

scan_user_files() {
    FOUND_USER_FILES=()
    local home="$REAL_HOME"
    local search_specs=(
        "$home/Library/Application Support:wondershare"
        "$home/Library/Application Support:com.wondershare.*"
        "$home/Library/Application Support:com.Wondershare.*"
        "$home/Library/Application Support:MediaDownloadKit"
        "$home/Library/Preferences:com.wondershare.*"
        "$home/Library/Preferences:com.Wondershare.*"
        "$home/Library/Preferences/ByHost:com.wondershare.*"
        "$home/Library/Preferences/ByHost:com.Wondershare.*"
        "$home/Library/Caches:com.wondershare.*"
        "$home/Library/Caches:com.Wondershare.*"
        "$home/Library/Caches/com.plausiblelabs.crashreporter.data:com.wondershare.*"
        "$home/Library/Caches/com.plausiblelabs.crashreporter.data:com.Wondershare.*"
        "$home/Library/Logs:Wondershare"
        "$home/Library/Logs:com.wondershare.*"
        "$home/Library/Logs:com.Wondershare.*"
        "$home/Library/Group Containers:*wondershare*"
        "$home/Library/Containers:com.wondershare.*"
        "$home/Library/Containers:com.Wondershare.*"
        "$home/Library/WebKit:com.wondershare.*"
        "$home/Library/WebKit:com.Wondershare.*"
        "$home/Library/HTTPStorages:com.wondershare.*"
        "$home/Library/HTTPStorages:com.Wondershare.*"
        "$home/Library/Application Scripts:*wondershare*"
        "$home/Library/Saved Application State:com.wondershare.*"
        "$home/Library/Saved Application State:com.Wondershare.*"
        "$home/Movies:Wondershare*"
    )

    local spec
    for spec in "${search_specs[@]}"; do
        local dir_part="${spec%%:*}"
        local name_part="${spec##*:}"
        if [[ -d "$dir_part" ]]; then
            while IFS= read -r match; do
                if [[ -n "$match" ]]; then
                    FOUND_USER_FILES+=("$match")
                    local size
                    size="$(dir_size_bytes "$match")"
                    TOTAL_SIZE=$((TOTAL_SIZE + size))
                fi
            done < <(find "$dir_part" -maxdepth 1 -iname "$name_part" 2>/dev/null || true)
        fi
    done
}

scan_root_files() {
    FOUND_ROOT_FILES=()
    local root_dirs=(
        "/private/var/root/Library/Application Support"
        "/private/var/root/Library/HTTPStorages"
        "/private/var/root/Library/Logs"
        "/private/var/root/Library/Caches"
        "/private/var/root/Library/Preferences"
    )
    local dir
    for dir in "${root_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            while IFS= read -r match; do
                if [[ -n "$match" ]]; then
                    FOUND_ROOT_FILES+=("$match")
                    local size
                    size="$(dir_size_bytes "$match")"
                    TOTAL_SIZE=$((TOTAL_SIZE + size))
                fi
            done < <(find "$dir" -maxdepth 1 -iname "*wondershare*" 2>/dev/null || true)
        fi
    done

    # Temp files
    if [[ -d "/private/tmp" ]]; then
        while IFS= read -r match; do
            if [[ -n "$match" ]]; then
                FOUND_ROOT_FILES+=("$match")
            fi
        done < <(find /private/tmp -maxdepth 1 -iname "*wondershare*" 2>/dev/null || true)
    fi

    # /private/var/folders deep scan
    while IFS= read -r match; do
        if [[ -n "$match" ]]; then
            FOUND_ROOT_FILES+=("$match")
        fi
    done < <(find /private/var/folders/ -maxdepth 5 -iname "*wondershare*" 2>/dev/null || true)
}

scan_all() {
    header "Scanning for Wondershare Artifacts"

    info "Scanning processes..."
    scan_processes

    info "Scanning applications..."
    scan_applications

    info "Scanning launch agents/daemons..."
    scan_launch_agents

    info "Scanning system files..."
    scan_system_files

    info "Scanning user files..."
    scan_user_files

    info "Scanning root/temp files..."
    scan_root_files

    echo ""
    print_scan_summary
}

print_scan_summary() {
    header "Scan Results"

    local total_items=0

    # Processes
    printf "${CYAN}%-30s${RESET} %d found\n" "Running Processes:" "${#FOUND_PROCESSES[@]}"
    if [[ ${#FOUND_PROCESSES[@]} -gt 0 ]]; then
        local proc
        for proc in "${FOUND_PROCESSES[@]}"; do
            printf "  ${DIM}%s${RESET}\n" "$proc"
        done
    fi
    total_items=$((total_items + ${#FOUND_PROCESSES[@]}))

    # Applications
    printf "${CYAN}%-30s${RESET} %d found\n" "Applications:" "${#FOUND_APPLICATIONS[@]}"
    if [[ ${#FOUND_APPLICATIONS[@]} -gt 0 ]]; then
        local app
        for app in "${FOUND_APPLICATIONS[@]}"; do
            local size_h
            size_h="$(bytes_to_human "$(dir_size_bytes "$app")")"
            printf "  ${DIM}%s (%s)${RESET}\n" "$app" "$size_h"
        done
    fi
    total_items=$((total_items + ${#FOUND_APPLICATIONS[@]}))

    # Launch Agents
    printf "${CYAN}%-30s${RESET} %d found\n" "Launch Agents/Daemons:" "${#FOUND_LAUNCH_AGENTS[@]}"
    if [[ ${#FOUND_LAUNCH_AGENTS[@]} -gt 0 ]]; then
        local agent
        for agent in "${FOUND_LAUNCH_AGENTS[@]}"; do
            printf "  ${DIM}%s${RESET}\n" "$agent"
        done
    fi
    total_items=$((total_items + ${#FOUND_LAUNCH_AGENTS[@]}))

    # System Files
    printf "${CYAN}%-30s${RESET} %d found\n" "System Files:" "${#FOUND_SYSTEM_FILES[@]}"
    if [[ ${#FOUND_SYSTEM_FILES[@]} -gt 0 ]]; then
        local sf
        for sf in "${FOUND_SYSTEM_FILES[@]}"; do
            printf "  ${DIM}%s${RESET}\n" "$sf"
        done
    fi
    total_items=$((total_items + ${#FOUND_SYSTEM_FILES[@]}))

    # User Files
    printf "${CYAN}%-30s${RESET} %d found\n" "User Files:" "${#FOUND_USER_FILES[@]}"
    if [[ ${#FOUND_USER_FILES[@]} -gt 0 ]]; then
        local uf
        for uf in "${FOUND_USER_FILES[@]}"; do
            printf "  ${DIM}%s${RESET}\n" "$uf"
        done
    fi
    total_items=$((total_items + ${#FOUND_USER_FILES[@]}))

    # Root/Temp Files
    printf "${CYAN}%-30s${RESET} %d found\n" "Root/Temp Files:" "${#FOUND_ROOT_FILES[@]}"
    if [[ ${#FOUND_ROOT_FILES[@]} -gt 0 ]]; then
        local rf
        for rf in "${FOUND_ROOT_FILES[@]}"; do
            printf "  ${DIM}%s${RESET}\n" "$rf"
        done
    fi
    total_items=$((total_items + ${#FOUND_ROOT_FILES[@]}))

    echo ""
    printf "${BOLD}Total artifacts: %d${RESET}\n" "$total_items"
    printf "${BOLD}Estimated size:  %s${RESET}\n" "$(bytes_to_human "$TOTAL_SIZE")"

    if [[ $total_items -eq 0 ]]; then
        echo ""
        success "No Wondershare artifacts found. This system appears clean."
    fi

    return "$total_items"
}

# =============================================================================
# Removal Functions
# =============================================================================

kill_processes() {
    header "Phase 1: Stopping Wondershare Processes"

    if [[ ${#FOUND_PROCESSES[@]} -eq 0 ]]; then
        info "No Wondershare processes running."
        return
    fi

    local pid
    local proc
    for proc in "${FOUND_PROCESSES[@]}"; do
        pid="$(echo "$proc" | awk '{print $1}')"
        if [[ -n "$pid" ]]; then
            if [[ $DRY_RUN -eq 1 ]]; then
                info "[DRY RUN] Would kill PID $pid: $proc"
            else
                kill "$pid" 2>/dev/null && info "Sent SIGTERM to PID $pid"
            fi
        fi
    done

    if [[ $DRY_RUN -eq 0 ]]; then
        info "Waiting 3 seconds for graceful shutdown..."
        sleep 3

        # SIGKILL survivors
        for proc in "${FOUND_PROCESSES[@]}"; do
            pid="$(echo "$proc" | awk '{print $1}')"
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                kill -9 "$pid" 2>/dev/null && warn "Force-killed PID $pid"
            fi
        done
    fi

    success "Process cleanup complete."
}

unload_launch_agents() {
    header "Phase 2: Unloading Launch Agents & Daemons"

    if [[ ${#FOUND_LAUNCH_AGENTS[@]} -eq 0 ]]; then
        info "No Wondershare launch agents/daemons found."
        return
    fi

    local plist
    for plist in "${FOUND_LAUNCH_AGENTS[@]}"; do
        local label
        label="$(/usr/libexec/PlistBuddy -c "Print :Label" "$plist" 2>/dev/null || true)"

        if [[ $DRY_RUN -eq 1 ]]; then
            info "[DRY RUN] Would unload: $plist (label: ${label:-unknown})"
            continue
        fi

        if [[ -n "$label" ]]; then
            # Try bootout first (modern launchctl), fall back to legacy unload
            if [[ "$plist" == *LaunchDaemons* ]]; then
                launchctl bootout "system/$label" 2>/dev/null ||
                    launchctl remove "$label" 2>/dev/null ||
                    launchctl unload -w "$plist" 2>/dev/null || true
            else
                local uid
                uid="$(id -u "$REAL_USER" 2>/dev/null || echo 501)"
                launchctl bootout "gui/$uid/$label" 2>/dev/null ||
                    launchctl remove "$label" 2>/dev/null ||
                    launchctl unload -w "$plist" 2>/dev/null || true
            fi
            info "Unloaded: $label"
        fi

        safe_remove "$plist"
    done

    success "Launch agents/daemons cleanup complete."
}

remove_applications() {
    header "Phase 3: Removing Wondershare Applications"

    if [[ ${#FOUND_APPLICATIONS[@]} -eq 0 ]]; then
        info "No Wondershare applications found."
        return
    fi

    local app
    for app in "${FOUND_APPLICATIONS[@]}"; do
        safe_remove "$app" "$(basename "$app")"
    done

    success "Application removal complete."
}

remove_system_files() {
    header "Phase 4: Removing System-Level Files"

    if [[ ${#FOUND_SYSTEM_FILES[@]} -eq 0 ]]; then
        info "No Wondershare system files found."
        return
    fi

    local sf
    for sf in "${FOUND_SYSTEM_FILES[@]}"; do
        safe_remove "$sf"
    done

    success "System file removal complete."
}

remove_user_files() {
    header "Phase 5: Removing User-Level Files"

    if [[ ${#FOUND_USER_FILES[@]} -eq 0 ]]; then
        info "No Wondershare user files found."
        return
    fi

    local uf
    for uf in "${FOUND_USER_FILES[@]}"; do
        safe_remove "$uf"
    done

    success "User file removal complete."
}

remove_root_files() {
    header "Phase 6: Removing Root & Temp Files"

    if [[ ${#FOUND_ROOT_FILES[@]} -eq 0 ]]; then
        info "No Wondershare root/temp files found."
        return
    fi

    local rf
    for rf in "${FOUND_ROOT_FILES[@]}"; do
        safe_remove "$rf"
    done

    success "Root/temp file removal complete."
}

system_cleanup() {
    header "Phase 7: System Cleanup"

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY RUN] Would refresh preferences cache (cfprefsd)"
        info "[DRY RUN] Would remove Wondershare login items"
        return
    fi

    # Refresh preferences daemon
    info "Refreshing preferences cache..."
    killall cfprefsd 2>/dev/null || true

    # Remove Wondershare login items via osascript
    info "Checking for Wondershare login items..."
    osascript -e '
        tell application "System Events"
            set loginItems to every login item
            repeat with anItem in loginItems
                if name of anItem contains "Wondershare" then
                    delete anItem
                end if
            end repeat
        end tell
    ' 2>/dev/null || warn "Could not modify login items (may need Full Disk Access)"

    success "System cleanup complete."
}

verify_removal() {
    header "Phase 8: Verification"

    info "Re-scanning for remaining Wondershare artifacts..."
    TOTAL_SIZE=0
    scan_processes
    scan_applications
    scan_launch_agents
    scan_system_files
    scan_user_files
    scan_root_files

    local remaining=0
    remaining=$((remaining + ${#FOUND_PROCESSES[@]}))
    remaining=$((remaining + ${#FOUND_APPLICATIONS[@]}))
    remaining=$((remaining + ${#FOUND_LAUNCH_AGENTS[@]}))
    remaining=$((remaining + ${#FOUND_SYSTEM_FILES[@]}))
    remaining=$((remaining + ${#FOUND_USER_FILES[@]}))
    remaining=$((remaining + ${#FOUND_ROOT_FILES[@]}))

    if [[ $remaining -eq 0 ]]; then
        success "All Wondershare artifacts have been removed!"
    else
        warn "$remaining artifact(s) remain (may be SIP-protected or in use):"
        print_scan_summary
    fi
}

remove_all() {
    kill_processes
    unload_launch_agents
    remove_applications
    remove_system_files
    remove_user_files
    remove_root_files
    system_cleanup

    if [[ $DRY_RUN -eq 0 ]]; then
        verify_removal
    fi

    if [[ -d "$RECOVERY_DIR" ]]; then
        echo ""
        info "Recovered files saved to: $RECOVERY_DIR"
        chown -R "$REAL_USER" "$RECOVERY_DIR" 2>/dev/null
    fi

    if [[ -n "$LOG_FILE" ]] && [[ -f "$LOG_FILE" ]]; then
        echo ""
        info "Full log saved to: $LOG_FILE"
    fi
}

# =============================================================================
# Interactive REPL Functions
# =============================================================================

shorten_path() {
    local path="$1"
    if [[ -n "$REAL_HOME" ]] && [[ "$path" == "$REAL_HOME"* ]]; then
        echo "~${path#$REAL_HOME}"
    else
        echo "$path"
    fi
}

build_item_list() {
    ITEM_PATHS=()
    ITEM_CATEGORIES=()
    ITEM_SELECTED=()
    ITEM_LABELS=()
    ITEM_SIZES=()

    local proc
    for proc in "${FOUND_PROCESSES[@]+"${FOUND_PROCESSES[@]}"}"; do
        ITEM_PATHS+=("$proc")
        ITEM_CATEGORIES+=("proc")
        ITEM_SELECTED+=(1)
        local pid label
        pid="$(echo "$proc" | awk '{print $1}')"
        label="$(echo "$proc" | awk '{$1=""; sub(/^ /, ""); print}')"
        ITEM_LABELS+=("PID $pid $label")
        ITEM_SIZES+=(0)
    done

    local app
    for app in "${FOUND_APPLICATIONS[@]+"${FOUND_APPLICATIONS[@]}"}"; do
        ITEM_PATHS+=("$app")
        ITEM_CATEGORIES+=("app")
        ITEM_SELECTED+=(1)
        local size
        size="$(dir_size_bytes "$app")"
        ITEM_LABELS+=("$(basename "$app")")
        ITEM_SIZES+=("$size")
    done

    local agent
    for agent in "${FOUND_LAUNCH_AGENTS[@]+"${FOUND_LAUNCH_AGENTS[@]}"}"; do
        ITEM_PATHS+=("$agent")
        ITEM_CATEGORIES+=("agent")
        ITEM_SELECTED+=(1)
        ITEM_LABELS+=("$(basename "$agent")")
        ITEM_SIZES+=(0)
    done

    local sf
    for sf in "${FOUND_SYSTEM_FILES[@]+"${FOUND_SYSTEM_FILES[@]}"}"; do
        ITEM_PATHS+=("$sf")
        ITEM_CATEGORIES+=("sys")
        ITEM_SELECTED+=(1)
        local size
        size="$(dir_size_bytes "$sf")"
        ITEM_LABELS+=("$(shorten_path "$sf")")
        ITEM_SIZES+=("$size")
    done

    local uf
    for uf in "${FOUND_USER_FILES[@]+"${FOUND_USER_FILES[@]}"}"; do
        ITEM_PATHS+=("$uf")
        ITEM_CATEGORIES+=("user")
        ITEM_SELECTED+=(1)
        local size
        size="$(dir_size_bytes "$uf")"
        ITEM_LABELS+=("$(shorten_path "$uf")")
        ITEM_SIZES+=("$size")
    done

    local rf
    for rf in "${FOUND_ROOT_FILES[@]+"${FOUND_ROOT_FILES[@]}"}"; do
        ITEM_PATHS+=("$rf")
        ITEM_CATEGORIES+=("root")
        ITEM_SELECTED+=(1)
        local size
        size="$(dir_size_bytes "$rf")"
        ITEM_LABELS+=("$(shorten_path "$rf")")
        ITEM_SIZES+=("$size")
    done
}

recalc_selected_size() {
    local total_size=0
    local i
    for ((i = 0; i < ${#ITEM_SIZES[@]}; i++)); do
        if [[ "${ITEM_SELECTED[$i]}" -eq 1 ]]; then
            total_size=$((total_size + ${ITEM_SIZES[$i]}))
        fi
    done
    echo "$total_size"
}

display_selection_summary() {
    local total=${#ITEM_PATHS[@]}
    local selected=0
    local i
    for ((i = 0; i < total; i++)); do
        if [[ "${ITEM_SELECTED[$i]}" -eq 1 ]]; then
            selected=$((selected + 1))
        fi
    done
    local size_h
    size_h="$(bytes_to_human "$(recalc_selected_size)")"
    printf "\n  ${BOLD}Selected: %d/%d items (%s)${RESET}\n" "$selected" "$total" "$size_h"
}

display_item_list() {
    local total=${#ITEM_PATHS[@]}
    if [[ $total -eq 0 ]]; then
        echo ""
        success "No Wondershare artifacts found. This system appears clean."
        return
    fi

    local cat_codes="proc app agent sys user root"
    local c
    for c in $cat_codes; do
        local cat_label
        case "$c" in
            proc)  cat_label="Running Processes" ;;
            app)   cat_label="Applications" ;;
            agent) cat_label="Launch Agents/Daemons" ;;
            sys)   cat_label="System Files" ;;
            user)  cat_label="User Files" ;;
            root)  cat_label="Root/Temp Files" ;;
        esac

        local count=0
        local i
        for ((i = 0; i < total; i++)); do
            if [[ "${ITEM_CATEGORIES[$i]}" == "$c" ]]; then
                count=$((count + 1))
            fi
        done

        if [[ $count -eq 0 ]]; then
            continue
        fi

        printf "\n  ${BOLD}━━━ %s (%d) ━━━${RESET}\n" "$cat_label" "$count"

        for ((i = 0; i < total; i++)); do
            if [[ "${ITEM_CATEGORIES[$i]}" != "$c" ]]; then
                continue
            fi

            local num=$((i + 1))
            local size_str=""
            if [[ "${ITEM_SIZES[$i]}" -gt 0 ]]; then
                size_str=" ($(bytes_to_human "${ITEM_SIZES[$i]}"))"
            fi

            if [[ "${ITEM_SELECTED[$i]}" -eq 1 ]]; then
                printf "   ${GREEN}[x]${RESET} %2d. %s${DIM}%s${RESET}\n" "$num" "${ITEM_LABELS[$i]}" "$size_str"
            else
                printf "   ${DIM}[ ] %2d. %s%s${RESET}\n" "$num" "${ITEM_LABELS[$i]}" "$size_str"
            fi
        done
    done

    display_selection_summary
}

repl_select_all() {
    local i
    for ((i = 0; i < ${#ITEM_PATHS[@]}; i++)); do
        ITEM_SELECTED[$i]=1
    done
    display_item_list
}

repl_select_none() {
    local i
    for ((i = 0; i < ${#ITEM_PATHS[@]}; i++)); do
        ITEM_SELECTED[$i]=0
    done
    display_item_list
}

repl_toggle_item() {
    local num="$1"
    local idx=$((num - 1))
    if [[ $idx -lt 0 ]] || [[ $idx -ge ${#ITEM_PATHS[@]} ]]; then
        warn "Invalid item number: $num (valid: 1-${#ITEM_PATHS[@]})"
        return
    fi
    if [[ "${ITEM_SELECTED[$idx]}" -eq 1 ]]; then
        ITEM_SELECTED[$idx]=0
    else
        ITEM_SELECTED[$idx]=1
    fi

    local size_str=""
    if [[ "${ITEM_SIZES[$idx]}" -gt 0 ]]; then
        size_str=" ($(bytes_to_human "${ITEM_SIZES[$idx]}"))"
    fi
    if [[ "${ITEM_SELECTED[$idx]}" -eq 1 ]]; then
        printf "   ${GREEN}[x]${RESET} %2d. %s${DIM}%s${RESET}\n" "$num" "${ITEM_LABELS[$idx]}" "$size_str"
    else
        printf "   ${DIM}[ ] %2d. %s%s${RESET}\n" "$num" "${ITEM_LABELS[$idx]}" "$size_str"
    fi
    display_selection_summary
    if [[ $REPL_FIRST_TOGGLE -eq 1 ]]; then
        REPL_FIRST_TOGGLE=0
        printf "  ${DIM}Tip: type 'remove' when ready, or 'list' to review all items${RESET}\n"
    fi
}

repl_select_range() {
    local action="$1"
    local range="$2"
    local val=1
    if [[ "$action" == "deselect" ]]; then
        val=0
    fi

    local start end
    if [[ "$range" == *-* ]]; then
        start="${range%-*}"
        end="${range#*-}"
    else
        start="$range"
        end="$range"
    fi

    if ! [[ "$start" =~ ^[0-9]+$ ]] || ! [[ "$end" =~ ^[0-9]+$ ]]; then
        warn "Invalid range: $range"
        return
    fi

    if [[ "$start" -lt 1 ]] || [[ "$end" -gt ${#ITEM_PATHS[@]} ]] || [[ "$start" -gt "$end" ]]; then
        warn "Invalid range: $range (valid: 1-${#ITEM_PATHS[@]})"
        return
    fi

    local i
    for ((i = start; i <= end; i++)); do
        local idx=$((i - 1))
        ITEM_SELECTED[$idx]=$val
    done
    display_item_list
}

repl_select_category() {
    local action="$1"
    local cat_input="$2"
    local val=1
    if [[ "$action" == "deselect" ]]; then
        val=0
    fi

    local cat_code=""
    case "$cat_input" in
        proc|procs|processes)  cat_code="proc" ;;
        app|apps|applications) cat_code="app" ;;
        agent|agents|daemons|launch) cat_code="agent" ;;
        sys|system)            cat_code="sys" ;;
        user)                  cat_code="user" ;;
        root|temp)             cat_code="root" ;;
        *)
            warn "Unknown category: $cat_input"
            echo "  Categories: proc, apps, agents, sys, user, root"
            return
            ;;
    esac

    local matched=0
    local i
    for ((i = 0; i < ${#ITEM_PATHS[@]}; i++)); do
        if [[ "${ITEM_CATEGORIES[$i]}" == "$cat_code" ]]; then
            ITEM_SELECTED[$i]=$val
            matched=$((matched + 1))
        fi
    done

    if [[ $matched -eq 0 ]]; then
        warn "No items in category: $cat_input"
    else
        display_item_list
    fi
}

repl_rescan() {
    TOTAL_SIZE=0
    info "Re-scanning for Wondershare artifacts..."
    echo ""
    scan_processes
    scan_applications
    scan_launch_agents
    scan_system_files
    scan_user_files
    scan_root_files
    build_item_list
    display_item_list
}

apply_selection_to_arrays() {
    local new_procs=()
    local new_apps=()
    local new_agents=()
    local new_sys=()
    local new_user=()
    local new_root=()

    local i
    for ((i = 0; i < ${#ITEM_PATHS[@]}; i++)); do
        if [[ "${ITEM_SELECTED[$i]}" -eq 0 ]]; then
            continue
        fi
        case "${ITEM_CATEGORIES[$i]}" in
            proc)  new_procs+=("${ITEM_PATHS[$i]}") ;;
            app)   new_apps+=("${ITEM_PATHS[$i]}") ;;
            agent) new_agents+=("${ITEM_PATHS[$i]}") ;;
            sys)   new_sys+=("${ITEM_PATHS[$i]}") ;;
            user)  new_user+=("${ITEM_PATHS[$i]}") ;;
            root)  new_root+=("${ITEM_PATHS[$i]}") ;;
        esac
    done

    FOUND_PROCESSES=("${new_procs[@]+"${new_procs[@]}"}")
    FOUND_APPLICATIONS=("${new_apps[@]+"${new_apps[@]}"}")
    FOUND_LAUNCH_AGENTS=("${new_agents[@]+"${new_agents[@]}"}")
    FOUND_SYSTEM_FILES=("${new_sys[@]+"${new_sys[@]}"}")
    FOUND_USER_FILES=("${new_user[@]+"${new_user[@]}"}")
    FOUND_ROOT_FILES=("${new_root[@]+"${new_root[@]}"}")
}

repl_confirm() {
    local item_count="$1"
    local total_size_human
    total_size_human="$(bytes_to_human "$TOTAL_SIZE")"

    printf "\n${RED}${BOLD}╔══════════════════════════════════════════════════╗${RESET}\n"
    printf "${RED}${BOLD}║          ⚠️  DESTRUCTIVE OPERATION  ⚠️            ║${RESET}\n"
    printf "${RED}${BOLD}╚══════════════════════════════════════════════════╝${RESET}\n\n"
    printf "  Items to remove:  ${BOLD}%d${RESET}\n" "$item_count"
    printf "  Estimated size:   ${BOLD}%s${RESET}\n" "$total_size_human"
    printf "  Recovery folder:  ${BOLD}%s${RESET}\n\n" "$RECOVERY_DIR"
    printf "  ${YELLOW}Protected files (WFP, EDDX, EMMX) will be copied${RESET}\n"
    printf "  ${YELLOW}to the recovery folder before removal.${RESET}\n\n"
    printf "  Type ${RED}${BOLD}REMOVE${RESET} to proceed, anything else to cancel: "

    local response
    read -r response
    if [[ "$response" != "REMOVE" ]]; then
        info "Operation cancelled."
        return 1
    fi
    echo ""
    return 0
}

repl_remove() {
    local selected=0
    local i
    for ((i = 0; i < ${#ITEM_PATHS[@]}; i++)); do
        if [[ "${ITEM_SELECTED[$i]}" -eq 1 ]]; then
            selected=$((selected + 1))
        fi
    done

    if [[ $selected -eq 0 ]]; then
        warn "No items selected. Use 'all' or select items first."
        return
    fi

    TOTAL_SIZE="$(recalc_selected_size)"

    if ! repl_confirm "$selected"; then
        return
    fi

    create_log_file
    apply_selection_to_arrays
    remove_all

    echo ""
    success "Wondershare removal complete!"
    cleanup_sudo_keepalive
    exit 0
}

repl_dryrun() {
    local selected=0
    local i
    for ((i = 0; i < ${#ITEM_PATHS[@]}; i++)); do
        if [[ "${ITEM_SELECTED[$i]}" -eq 1 ]]; then
            selected=$((selected + 1))
        fi
    done

    if [[ $selected -eq 0 ]]; then
        warn "No items selected. Use 'all' or select items first."
        return
    fi

    # Save current arrays so we can restore after dry run
    local saved_procs=("${FOUND_PROCESSES[@]+"${FOUND_PROCESSES[@]}"}")
    local saved_apps=("${FOUND_APPLICATIONS[@]+"${FOUND_APPLICATIONS[@]}"}")
    local saved_agents=("${FOUND_LAUNCH_AGENTS[@]+"${FOUND_LAUNCH_AGENTS[@]}"}")
    local saved_sys=("${FOUND_SYSTEM_FILES[@]+"${FOUND_SYSTEM_FILES[@]}"}")
    local saved_user=("${FOUND_USER_FILES[@]+"${FOUND_USER_FILES[@]}"}")
    local saved_root=("${FOUND_ROOT_FILES[@]+"${FOUND_ROOT_FILES[@]}"}")
    local saved_total="$TOTAL_SIZE"

    DRY_RUN=1
    TOTAL_SIZE="$(recalc_selected_size)"
    apply_selection_to_arrays
    remove_all

    # Restore arrays
    FOUND_PROCESSES=("${saved_procs[@]+"${saved_procs[@]}"}")
    FOUND_APPLICATIONS=("${saved_apps[@]+"${saved_apps[@]}"}")
    FOUND_LAUNCH_AGENTS=("${saved_agents[@]+"${saved_agents[@]}"}")
    FOUND_SYSTEM_FILES=("${saved_sys[@]+"${saved_sys[@]}"}")
    FOUND_USER_FILES=("${saved_user[@]+"${saved_user[@]}"}")
    FOUND_ROOT_FILES=("${saved_root[@]+"${saved_root[@]}"}")
    TOTAL_SIZE="$saved_total"
    DRY_RUN=0

    echo ""
    info "Dry run complete. No files were modified."
}

repl_welcome() {
    printf "\n"
    printf "  ${BOLD}What next?${RESET}\n"
    printf "  All items above are selected for removal.\n"
    printf "\n"
    printf "  ${GREEN}${BOLD}remove${RESET}       Remove selected items (asks to confirm)\n"
    printf "  ${YELLOW}keep N${RESET}       Keep an item (deselect from removal)\n"
    printf "  ${YELLOW}keep 3-7${RESET}     Keep a range of items\n"
    printf "  ${YELLOW}keep apps${RESET}    Keep an entire category\n"
    printf "  ${DIM}help         Full command reference${RESET}\n"
}

repl_help() {
    printf "\n"
    printf "  ${BOLD}━━━ Quick Start ━━━${RESET}\n"
    printf "  Everything is selected. Deselect what you want to keep,\n"
    printf "  then type ${GREEN}${BOLD}remove${RESET} to delete the rest.\n"
    printf "\n"
    printf "  ${BOLD}━━━ Actions ━━━${RESET}\n"
    printf "    remove         Remove selected items (with confirmation)\n"
    printf "    dry-run        Preview what would be removed\n"
    printf "    list           Redisplay the item list\n"
    printf "    rescan         Re-scan system (resets selections)\n"
    printf "\n"
    printf "  ${BOLD}━━━ Adjusting Selection ━━━${RESET}\n"
    printf "    N              Toggle item N on/off\n"
    printf "    keep N         Deselect item N (keep it on disk)\n"
    printf "    keep N-M       Deselect items N through M\n"
    printf "    keep apps      Deselect entire category\n"
    printf "    select N       Reselect item N for removal\n"
    printf "    select N-M     Reselect items N through M\n"
    printf "    select apps    Reselect entire category\n"
    printf "    all / none     Select or deselect everything\n"
    printf "\n"
    printf "  ${BOLD}━━━ Categories ━━━${RESET}\n"
    printf "    processes  apps  agents  system  user  root\n"
    printf "\n"
    printf "  ${BOLD}━━━ Other ━━━${RESET}\n"
    printf "    help, h, ?     Show this help\n"
    printf "    quit, q        Exit without removing\n"
    printf "\n"
}

repl_quit() {
    echo ""
    info "Goodbye."
    cleanup_sudo_keepalive
    exit 0
}

repl_parse_command() {
    local input="$1"
    input="$(echo "$input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    if [[ -z "$input" ]]; then
        return
    fi

    case "$input" in
        q|quit|exit)
            repl_quit
            ;;
        help|h|\?)
            repl_help
            ;;
        all)
            repl_select_all
            ;;
        none)
            repl_select_none
            ;;
        list|ls|l)
            display_item_list
            ;;
        rescan)
            repl_rescan
            ;;
        remove)
            repl_remove
            ;;
        dry-run|dryrun)
            repl_dryrun
            ;;
        select\ *)
            local arg="${input#select }"
            if [[ "$arg" =~ ^[0-9]+(-[0-9]+)?$ ]]; then
                repl_select_range "select" "$arg"
            else
                repl_select_category "select" "$arg"
            fi
            ;;
        deselect\ *)
            local arg="${input#deselect }"
            if [[ "$arg" =~ ^[0-9]+(-[0-9]+)?$ ]]; then
                repl_select_range "deselect" "$arg"
            else
                repl_select_category "deselect" "$arg"
            fi
            ;;
        keep\ *)
            local arg="${input#keep }"
            if [[ "$arg" =~ ^[0-9]+(-[0-9]+)?$ ]]; then
                repl_select_range "deselect" "$arg"
            else
                repl_select_category "deselect" "$arg"
            fi
            ;;
        *)
            # Bare number = toggle
            if [[ "$input" =~ ^[0-9]+$ ]]; then
                repl_toggle_item "$input"
            else
                warn "Unknown command: $input"
                echo "  Type 'help' for available commands."
            fi
            ;;
    esac
}

cmd_interactive() {
    require_sudo interactive
    get_real_user

    printf "\n${BOLD}Wondershare macOS Remover v${VERSION}${RESET}\n"

    TOTAL_SIZE=0
    info "Scanning for Wondershare artifacts..."
    echo ""
    scan_processes
    scan_applications
    scan_launch_agents
    scan_system_files
    scan_user_files
    scan_root_files

    build_item_list
    display_item_list

    if [[ ${#ITEM_PATHS[@]} -eq 0 ]]; then
        cleanup_sudo_keepalive
        return
    fi

    repl_welcome

    while true; do
        printf "\n${CYAN}wondershare>${RESET} "
        local input
        if ! read -r input; then
            repl_quit
        fi
        repl_parse_command "$input"
    done
}

# =============================================================================
# Command Handlers
# =============================================================================

cmd_scan() {
    require_sudo scan
    get_real_user
    scan_all
}

cmd_remove() {
    require_sudo remove
    get_real_user
    create_log_file

    info "Starting Wondershare removal process..."
    scan_all

    # Get total item count
    local total_items=0
    total_items=$((total_items + ${#FOUND_PROCESSES[@]}))
    total_items=$((total_items + ${#FOUND_APPLICATIONS[@]}))
    total_items=$((total_items + ${#FOUND_LAUNCH_AGENTS[@]}))
    total_items=$((total_items + ${#FOUND_SYSTEM_FILES[@]}))
    total_items=$((total_items + ${#FOUND_USER_FILES[@]}))
    total_items=$((total_items + ${#FOUND_ROOT_FILES[@]}))

    if [[ $total_items -eq 0 ]]; then
        success "Nothing to remove. System is already clean."
        cleanup_sudo_keepalive
        return
    fi

    if [[ $FORCE -eq 0 ]] && [[ $DRY_RUN -eq 0 ]]; then
        confirm_action "$total_items"
    fi

    remove_all

    echo ""
    if [[ $DRY_RUN -eq 1 ]]; then
        info "Dry run complete. No files were modified."
    else
        success "Wondershare removal complete!"
    fi

    cleanup_sudo_keepalive
}

cmd_help() {
    cat <<HELP
Wondershare macOS Remover v${VERSION}
Complete removal of Wondershare products and all related artifacts from macOS.

USAGE
    sudo ./wondershare-remover.sh              Interactive mode (recommended)
    sudo ./wondershare-remover.sh <command>    CLI mode

COMMANDS
    (none)      Launch interactive mode — scan, select items, then remove
    scan        Scan and report all Wondershare artifacts (read-only)
    remove      Scan, confirm, then remove everything (no selection)
    help        Show this help message
    version     Show version

OPTIONS
    --force         Skip the confirmation prompt (use with caution)
    --dry-run       Show what would be removed without deleting anything
    --no-color      Disable colored output
    --log-dir DIR   Custom log directory (default: ~/Desktop)

EXAMPLES
    sudo ./wondershare-remover.sh
    sudo ./wondershare-remover.sh scan
    sudo ./wondershare-remover.sh remove --dry-run
    sudo ./wondershare-remover.sh remove
    sudo ./wondershare-remover.sh remove --force --log-dir /tmp

PROTECTED FILES
    Files with project extensions (WFP, EDDX, EMMX)
    found outside /Applications/ are automatically copied to:
        ~/Desktop/Wondershare-Recovered-Files/
    before their parent directory is removed.

MORE INFO
    https://github.com/darrenallatt/wondershare-macos-remover
HELP
}

cmd_version() {
    echo "Wondershare macOS Remover v${VERSION}"
}

# =============================================================================
# Argument Parser & Main
# =============================================================================

main() {
    local command=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            scan|remove|help|version)
                command="$1"
                shift
                ;;
            --force)
                FORCE=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --no-color)
                RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" BOLD="" DIM="" RESET=""
                shift
                ;;
            --log-dir)
                if [[ -z "${2:-}" ]]; then
                    error "--log-dir requires a directory argument"
                    exit 1
                fi
                LOG_DIR="$2"
                shift 2
                ;;
            -h|--help)
                command="help"
                shift
                ;;
            -v|--version)
                command="version"
                shift
                ;;
            *)
                error "Unknown argument: $1"
                echo "Run '$0 help' for usage information."
                exit 1
                ;;
        esac
    done

    if [[ -z "$command" ]]; then
        cmd_interactive
        exit 0
    fi

    # Trap for cleanup
    trap cleanup_sudo_keepalive EXIT

    case "$command" in
        scan)    cmd_scan ;;
        remove)  cmd_remove ;;
        help)    cmd_help ;;
        version) cmd_version ;;
    esac
}

main "$@"
