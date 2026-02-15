#!/usr/bin/env bash
set -euo pipefail

# install.sh — cc-otel turnkey installer
# Automates: prerequisite checks, Docker stack launch, health verification,
# shell detection, and environment variable injection.
#
# Usage:
#   ./install.sh              # auto-detect shell, launch stack, inject env vars
#   ./install.sh --shell zsh  # override shell detection
#   curl ... | bash           # auto-clone mode (fetches repo first)

# =============================================================================
# Constants
# =============================================================================

readonly CC_OTEL_VERSION="0.1.0"
readonly CC_OTEL_REPO="https://github.com/anthropics/cc-otel.git"
readonly CC_OTEL_DEFAULT_HOME="${CC_OTEL_HOME:-$HOME/.cc-otel}"

readonly SENTINEL_BEGIN="# >>> cc-otel >>>"
readonly SENTINEL_END="# <<< cc-otel <<<"

readonly HEALTH_TIMEOUT=60
readonly HEALTH_BACKOFF_CAP=8

# Service health endpoints (name:url pairs, no associative arrays for bash 3.2)
readonly HEALTH_NAMES="otel-collector prometheus loki grafana"
readonly HEALTH_URL_OTEL_COLLECTOR="http://localhost:13133"
readonly HEALTH_URL_PROMETHEUS="http://localhost:9090/-/healthy"
readonly HEALTH_URL_LOKI="http://localhost:3100/ready"
readonly HEALTH_URL_GRAFANA="http://localhost:3000/api/health"

# =============================================================================
# Logging utilities
# =============================================================================

_log() {
    local level="$1"; shift
    printf '[%s] %s\n' "$level" "$*" >&2
}

info()    { _log "INFO"    "$@"; }
warn()    { _log "WARN"    "$@"; }
error()   { _log "ERROR"   "$@"; }
success() { _log "OK"      "$@"; }

die() {
    error "$@"
    exit 1
}

# =============================================================================
# Argument parsing
# =============================================================================

SHELL_OVERRIDE=""

usage() {
    cat <<'USAGE'
Usage: install.sh [OPTIONS]

Options:
  --shell <bash|zsh|fish>   Override automatic shell detection
  --help                    Show this help message
  --version                 Show version

Environment:
  CC_OTEL_HOME              Installation directory (default: ~/.cc-otel)
USAGE
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --shell)
                [ $# -ge 2 ] || die "--shell requires an argument (bash, zsh, or fish)"
                SHELL_OVERRIDE="$2"
                case "$SHELL_OVERRIDE" in
                    bash|zsh|fish) ;;
                    *) die "Unsupported shell: $SHELL_OVERRIDE (expected bash, zsh, or fish)" ;;
                esac
                shift 2
                ;;
            --help)
                usage
                exit 0
                ;;
            --version)
                printf 'cc-otel installer %s\n' "$CC_OTEL_VERSION"
                exit 0
                ;;
            *)
                die "Unknown option: $1 (see --help)"
                ;;
        esac
    done
}

# =============================================================================
# Prerequisite checks
# =============================================================================

check_prerequisites() {
    info "Checking prerequisites..."

    # Bash version (informational — we target 3.2+)
    local bash_major
    bash_major="${BASH_VERSINFO[0]}"
    if [ "$bash_major" -lt 3 ]; then
        die "Bash 3.2+ is required (found $BASH_VERSION)"
    fi

    # Docker
    if ! command -v docker >/dev/null 2>&1; then
        die "Docker is not installed. Please install Docker: https://docs.docker.com/get-docker/"
    fi

    if ! docker info >/dev/null 2>&1; then
        die "Docker daemon is not running. Please start Docker and try again."
    fi

    # Docker Compose v2+
    if ! docker compose version >/dev/null 2>&1; then
        die "Docker Compose v2 is required. 'docker compose' plugin not found."
    fi

    local compose_version
    compose_version="$(docker compose version --short 2>/dev/null || docker compose version 2>/dev/null)"
    # Extract major version number
    local compose_major
    compose_major="$(printf '%s' "$compose_version" | sed 's/^v//; s/\..*//')"
    if [ -n "$compose_major" ] && [ "$compose_major" -lt 2 ] 2>/dev/null; then
        die "Docker Compose v2+ is required (found $compose_version)"
    fi

    # curl or wget (for health checks)
    if command -v curl >/dev/null 2>&1; then
        FETCH_CMD="curl"
    elif command -v wget >/dev/null 2>&1; then
        FETCH_CMD="wget"
    else
        die "curl or wget is required for health checks. Please install one."
    fi

    # git (needed for auto-clone mode)
    if ! command -v git >/dev/null 2>&1; then
        warn "git is not installed. Auto-clone mode will not be available."
        HAS_GIT=false
    else
        HAS_GIT=true
    fi

    success "All prerequisites satisfied"
}

# =============================================================================
# HTTP fetch helper (abstracts curl vs wget)
# =============================================================================

http_check() {
    local url="$1"
    local timeout="${2:-5}"
    if [ "$FETCH_CMD" = "curl" ]; then
        curl -sf --max-time "$timeout" "$url" >/dev/null 2>&1
    else
        wget -q --timeout="$timeout" -O /dev/null "$url" 2>/dev/null
    fi
}

# =============================================================================
# Repository setup
# =============================================================================

setup_repo() {
    # If docker-compose.yml exists in the script's directory, we're running from a clone
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"

    if [ -f "$script_dir/docker-compose.yml" ]; then
        REPO_DIR="$script_dir"
        info "Running from existing repository at $REPO_DIR"
        return 0
    fi

    # Auto-clone mode (curl-pipe-bash scenario)
    info "docker-compose.yml not found — entering auto-clone mode"

    if [ "$HAS_GIT" = "false" ]; then
        die "git is required for auto-clone mode but is not installed"
    fi

    REPO_DIR="$CC_OTEL_DEFAULT_HOME"

    if [ -d "$REPO_DIR/.git" ]; then
        info "Existing clone found at $REPO_DIR — pulling latest changes"
        git -C "$REPO_DIR" pull --ff-only >> /dev/null 2>&1 || warn "Could not pull latest changes; continuing with existing clone"
    else
        info "Cloning cc-otel to $REPO_DIR..."
        git clone "$CC_OTEL_REPO" "$REPO_DIR" || die "Failed to clone repository"
    fi

    if [ ! -f "$REPO_DIR/docker-compose.yml" ]; then
        die "docker-compose.yml not found in $REPO_DIR after clone"
    fi

    success "Repository ready at $REPO_DIR"
}

# =============================================================================
# Docker stack launch
# =============================================================================

launch_stack() {
    info "Launching Docker Compose stack..."

    docker compose -f "$REPO_DIR/docker-compose.yml" up -d >> /dev/null 2>&1 \
        || die "Failed to start Docker Compose stack"

    success "Docker Compose stack started"
}

# =============================================================================
# Health check polling (exponential backoff)
# =============================================================================

get_health_url() {
    local service="$1"
    case "$service" in
        otel-collector) printf '%s' "$HEALTH_URL_OTEL_COLLECTOR" ;;
        prometheus)     printf '%s' "$HEALTH_URL_PROMETHEUS" ;;
        loki)           printf '%s' "$HEALTH_URL_LOKI" ;;
        grafana)        printf '%s' "$HEALTH_URL_GRAFANA" ;;
        *)              die "Unknown service: $service" ;;
    esac
}

poll_service() {
    local service="$1"
    local url
    url="$(get_health_url "$service")"

    local elapsed=0
    local delay=1

    while [ "$elapsed" -lt "$HEALTH_TIMEOUT" ]; do
        if http_check "$url" 3; then
            return 0
        fi
        sleep "$delay"
        elapsed=$((elapsed + delay))
        delay=$((delay * 2))
        if [ "$delay" -gt "$HEALTH_BACKOFF_CAP" ]; then
            delay=$HEALTH_BACKOFF_CAP
        fi
    done

    return 1
}

wait_for_services() {
    info "Waiting for services to become healthy (timeout: ${HEALTH_TIMEOUT}s)..."

    local failed=""
    local service
    for service in $HEALTH_NAMES; do
        printf '  Checking %s... ' "$service" >&2
        if poll_service "$service"; then
            printf 'healthy\n' >&2
        else
            printf 'FAILED\n' >&2
            failed="$failed $service"
        fi
    done

    if [ -n "$failed" ]; then
        die "The following services did not become healthy:$failed"
    fi

    success "All 4 services are healthy"
}

# =============================================================================
# Shell detection
# =============================================================================

detect_shell() {
    if [ -n "$SHELL_OVERRIDE" ]; then
        printf '%s' "$SHELL_OVERRIDE"
        return 0
    fi

    local shell_name
    shell_name="$(basename "${SHELL:-/bin/bash}")"

    case "$shell_name" in
        bash|zsh|fish) printf '%s' "$shell_name" ;;
        *)
            warn "Unsupported shell '$shell_name' — falling back to bash"
            printf 'bash'
            ;;
    esac
}

# =============================================================================
# Shell profile resolution
# =============================================================================

resolve_shell_profile() {
    local shell_name="$1"

    case "$shell_name" in
        bash)
            # macOS uses .bash_profile for login shells
            if [ -f "$HOME/.bash_profile" ]; then
                printf '%s' "$HOME/.bash_profile"
            elif [ -f "$HOME/.bashrc" ]; then
                printf '%s' "$HOME/.bashrc"
            else
                # Create .bashrc as the default
                printf '%s' "$HOME/.bashrc"
            fi
            ;;
        zsh)
            printf '%s' "$HOME/.zshrc"
            ;;
        fish)
            printf '%s' "$HOME/.config/fish/config.fish"
            ;;
        *)
            die "Cannot resolve profile for shell: $shell_name"
            ;;
    esac
}

# =============================================================================
# Profile block generation (reusable by tasks 03/04)
# =============================================================================

generate_profile_block() {
    local shell_name="$1"

    case "$shell_name" in
        bash|zsh)
            cat <<'BLOCK'
# >>> cc-otel >>>
# Managed by cc-otel installer — do not edit manually
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4317"
export OTEL_EXPORTER_OTLP_PROTOCOL="grpc"
export OTEL_METRICS_EXPORTER="otlp"
export OTEL_LOGS_EXPORTER="otlp"
# <<< cc-otel <<<
BLOCK
            ;;
        fish)
            cat <<'BLOCK'
# >>> cc-otel >>>
# Managed by cc-otel installer — do not edit manually
set -gx CLAUDE_CODE_ENABLE_TELEMETRY 1
set -gx OTEL_EXPORTER_OTLP_ENDPOINT "http://localhost:4317"
set -gx OTEL_EXPORTER_OTLP_PROTOCOL "grpc"
set -gx OTEL_METRICS_EXPORTER "otlp"
set -gx OTEL_LOGS_EXPORTER "otlp"
# <<< cc-otel <<<
BLOCK
            ;;
        *)
            die "Cannot generate profile block for shell: $shell_name"
            ;;
    esac
}

# =============================================================================
# Sentinel-fenced injection (reusable by tasks 03/04)
# =============================================================================

inject_or_update_profile() {
    local profile_path="$1"
    local shell_name="$2"

    # Ensure parent directories exist (needed for fish)
    local profile_dir
    profile_dir="$(dirname "$profile_path")"
    mkdir -p "$profile_dir"

    # Create file if it doesn't exist
    if [ ! -f "$profile_path" ]; then
        touch "$profile_path"
        info "Created $profile_path"
    fi

    # Backup before modifying
    cp "$profile_path" "${profile_path}.cc-otel-backup"
    info "Backup saved to ${profile_path}.cc-otel-backup"

    # Generate the new block
    local new_block
    new_block="$(generate_profile_block "$shell_name")"

    # Strip any existing cc-otel block using awk, then append the new block.
    # Write to a temp file and mv for atomicity.
    local tmp_file
    tmp_file="$(mktemp)"

    awk -v begin="$SENTINEL_BEGIN" -v end="$SENTINEL_END" '
        $0 == begin { skip = 1; next }
        $0 == end   { skip = 0; next }
        !skip       { print }
    ' "$profile_path" > "$tmp_file"

    # Ensure file ends with a newline before appending
    if [ -s "$tmp_file" ]; then
        # Check if file ends with newline
        local last_char
        last_char="$(tail -c 1 "$tmp_file" 2>/dev/null || true)"
        if [ -n "$last_char" ]; then
            printf '\n' >> "$tmp_file"
        fi
    fi

    # Append new block
    printf '%s\n' "$new_block" >> "$tmp_file"

    # Atomic replace
    mv "$tmp_file" "$profile_path"

    success "Environment variables injected into $profile_path"
}

# =============================================================================
# Summary output
# =============================================================================

print_summary() {
    local shell_name="$1"
    local profile_path="$2"

    cat >&2 <<EOF

============================================================
  cc-otel setup complete!
============================================================

  Stack status:
    OTel Collector  http://localhost:13133   healthy
    Prometheus      http://localhost:9090    healthy
    Loki            http://localhost:3100    healthy
    Grafana         http://localhost:3000    healthy

  Shell configuration:
    Shell:    $shell_name
    Profile:  $profile_path
    Backup:   ${profile_path}.cc-otel-backup

  Next steps:
    1. Restart your shell or run:
         source $profile_path
    2. Start a Claude Code session — telemetry will flow automatically
    3. Open Grafana: http://localhost:3000

  To stop the stack:
    docker compose -f $REPO_DIR/docker-compose.yml down

============================================================
EOF
}

# =============================================================================
# Main orchestrator
# =============================================================================

main() {
    parse_args "$@"

    info "cc-otel installer v${CC_OTEL_VERSION}"

    check_prerequisites
    setup_repo
    launch_stack
    wait_for_services

    local shell_name
    shell_name="$(detect_shell)"
    info "Detected shell: $shell_name"

    local profile_path
    profile_path="$(resolve_shell_profile "$shell_name")"
    info "Target profile: $profile_path"

    inject_or_update_profile "$profile_path" "$shell_name"

    print_summary "$shell_name" "$profile_path"
}

main "$@"
