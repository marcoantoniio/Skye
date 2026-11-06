#!/usr/bin/env bash
#
# Skye installer.
#
# Installs the Quickshell configuration into
# ~/.config/quickshell/skye (or $XDG_CONFIG_HOME/quickshell/skye), creates a
# systemd user service and starts the shell.
#
# The script is safe to run from the repository itself: if the checkout is
# already in the target directory, it only checks the dependencies and
# service.
#
# Usage: ./install.sh [options]

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
TARGET="$CONFIG_HOME/quickshell/skye"
SERVICE_DIR="$CONFIG_HOME/systemd/user"
SERVICE_FILE="$SERVICE_DIR/skye.service"
MIDEA_VENV="$HOME/.local/share/skye/midea-venv"

INSTALL_DEPS=0
WITH_MIDEA=0
NO_SERVICE=0
NO_START=0
DRY_RUN=0

if [ -t 1 ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
    C_BLUE=$'\033[34m'
else
    C_RESET=""
    C_BOLD=""
    C_GREEN=""
    C_YELLOW=""
    C_RED=""
    C_BLUE=""
fi

info() { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok() { printf '%s ok %s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s warn %s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() {
    printf '%s error %s %s\n' "$C_RED" "$C_RESET" "$*" >&2
    exit 1
}

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '%s[dry-run]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"
    else
        "$@"
    fi
}

usage() {
    cat <<EOF
Skye installer

Usage: ./install.sh [options]

Options:
  --install-deps   Install required packages on Arch/CachyOS (pacman)
  --with-midea     Create the Python venv used by the Midea AC bridge
  --no-service     Do not create or enable the systemd user service
  --no-start       Do not start Skye after installing
  --dry-run        Print the actions without changing anything
  -h, --help       Show this help

The shell configuration is installed in:
  $TARGET

Optional integrations (Proton Calendar, Midea credentials and Discord) are
documented in README.md and are not configured automatically.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --install-deps) INSTALL_DEPS=1 ;;
        --with-midea) WITH_MIDEA=1 ;;
        --no-service) NO_SERVICE=1 ;;
        --no-start) NO_START=1 ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            printf 'Unknown option: %s\n\n' "$arg" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ ! -f "$SCRIPT_DIR/shell.qml" ]; then
    die "shell.qml not found in $SCRIPT_DIR. Run this script from the repository root."
fi

install_deps() {
    if ! command -v pacman >/dev/null 2>&1; then
        warn "Automatic dependency installation is only implemented for Arch/CachyOS."
        warn "Install quickshell, a Nerd Font and curl with your package manager."
        return
    fi

    info "Installing required packages: quickshell, ttf-jetbrains-mono-nerd, curl"
    if [ "$(id -u)" -eq 0 ]; then
        run pacman -S --needed --noconfirm quickshell ttf-jetbrains-mono-nerd curl
    elif command -v sudo >/dev/null 2>&1; then
        run sudo pacman -S --needed --noconfirm quickshell ttf-jetbrains-mono-nerd curl
    else
        warn "sudo not found; install the packages manually."
    fi
}

check_deps() {
    local missing=0
    local qs_version=""

    if command -v qs >/dev/null 2>&1; then
        qs_version="$(qs --version 2>/dev/null | awk '{print $2}')"
        ok "quickshell ${qs_version:-unknown}"

        if [ -n "$qs_version" ] \
            && [ "$(printf '%s\n' "0.3.1" "$qs_version" | sort -V | sed -n '1p')" != "0.3.1" ]; then
            warn "Quickshell 0.3.1 or newer is recommended (found $qs_version)."
        fi
    else
        warn "quickshell (qs) not found."
        missing=1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        warn "curl not found: weather, lyrics and album art will not work."
    fi

    if command -v fc-list >/dev/null 2>&1; then
        if ! fc-list 2>/dev/null | grep -iE 'nerd|JetBrainsMono' >/dev/null; then
            warn "Nerd Font not found: icons may appear as empty boxes."
        fi
    fi

    if [ "$missing" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
        die "Install quickshell first, or rerun with --install-deps."
    fi
}

install_files() {
    if [ -d "$TARGET" ] \
        && [ "$(realpath -m "$TARGET")" = "$(realpath -m "$SCRIPT_DIR")" ]; then
        ok "Using the current checkout at $TARGET"
        return
    fi

    if [ -e "$TARGET" ]; then
        die "Target already exists: $TARGET
Move it away (or update it) and run the installer again."
    fi

    info "Installing Skye into $TARGET"
    run mkdir -p "$(dirname "$TARGET")"
    run cp -a "$SCRIPT_DIR" "$TARGET"
}

install_service() {
    if [ "$NO_SERVICE" -eq 1 ]; then
        info "Skipping the systemd user service (--no-service)."
        return 1
    fi

    if ! command -v systemctl >/dev/null 2>&1 \
        || ! systemctl --user show-environment >/dev/null 2>&1; then
        warn "No systemd user session; starting Skye directly instead."
        return 1
    fi

    if [ -f "$SERVICE_FILE" ]; then
        ok "Using existing service: $SERVICE_FILE"
    else
        info "Creating $SERVICE_FILE"
        if [ "$DRY_RUN" -eq 1 ]; then
            printf '%s[dry-run]%s write %s\n' "$C_YELLOW" "$C_RESET" "$SERVICE_FILE"
        else
            mkdir -p "$SERVICE_DIR"
            cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Skye (Quickshell shell)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=$(command -v qs) -c skye -n
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=graphical-session.target
EOF
        fi
    fi

    run systemctl --user daemon-reload
    run systemctl --user enable skye.service

    if [ "$NO_START" -eq 1 ]; then
        info "Service enabled; Skye will start with the next session."
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        run systemctl --user restart skye.service
    elif systemctl --user is-active --quiet skye.service; then
        run systemctl --user restart skye.service
    else
        run systemctl --user start skye.service
    fi
}

setup_midea() {
    if [ "$WITH_MIDEA" -eq 0 ]; then
        return
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        warn "python3 not found; skipping the Midea environment."
        return
    fi

    info "Creating the Midea Python environment at $MIDEA_VENV"
    run mkdir -p "$(dirname "$MIDEA_VENV")"
    run python3 -m venv "$MIDEA_VENV"
    run "$MIDEA_VENV/bin/pip" install --upgrade pip msmart-ng

    if [ "$DRY_RUN" -eq 0 ]; then
        cat <<EOF

Midea environment ready. Extract the unit credentials with:

  $MIDEA_VENV/bin/msmart-ng discover --account 'YOUR_ACCOUNT' --password 'YOUR_PASSWORD'

Then create ~/.config/skye/midea.json with the printed ip, port, id, token
and key, and restrict it with:

  chmod 600 ~/.config/skye/midea.json

See the "Midea air conditioner" section in README.md for details.
EOF
    fi
}

if [ "$INSTALL_DEPS" -eq 1 ]; then
    install_deps
fi

check_deps
install_files
setup_midea

SERVICE_HANDLED=0
if install_service; then
    SERVICE_HANDLED=1
fi

if [ "$NO_START" -eq 0 ] && [ "$SERVICE_HANDLED" -eq 0 ]; then
    info "Starting Skye"
    run qs -c skye -n -d
fi

printf '\n'
if [ "$DRY_RUN" -eq 1 ]; then
    ok "Dry run complete; no changes were made."
    exit 0
fi

ok "Skye installed."
if [ "$NO_START" -eq 1 ]; then
    if [ "$SERVICE_HANDLED" -eq 1 ]; then
        printf 'Start it later with: systemctl --user start skye.service\n'
    else
        printf 'Start it later with: qs -c skye -n -d\n'
    fi
elif [ "$SERVICE_HANDLED" -eq 1 ]; then
    printf 'Skye is running through the systemd user service.\n'
else
    printf 'Skye was started with qs.\n'
fi
printf 'Optional integrations: see README.md (Proton Calendar, Midea, Discord).\n'
