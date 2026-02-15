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

readonly TOTAL_STEPS=6

# =============================================================================
# Color & formatting infrastructure
# =============================================================================

# Detect interactive terminal
INTERACTIVE=false
if [ -t 0 ] && [ -t 1 ]; then
    INTERACTIVE=true
fi

# Detect color support
USE_COLOR=false
if [ -z "${NO_COLOR:-}" ] && [ "$INTERACTIVE" = true ]; then
    if command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
        USE_COLOR=true
    fi
fi

# Set color variables via tput (or empty strings when color is disabled)
if [ "$USE_COLOR" = true ]; then
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
    BOLD="$(tput bold)"
    RESET="$(tput sgr0)"
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    BOLD=""
    RESET=""
fi

# Emoji vs ASCII fallback for non-interactive terminals
if [ "$INTERACTIVE" = true ]; then
    ICO_OK="✅"
    ICO_ERR="❌"
    ICO_WARN="⚠️ "
    ICO_SEARCH="🔍"
    ICO_PACKAGE="📦"
    ICO_DOCKER="🐳"
    ICO_HEALTH="🏥"
    ICO_SHELL="🐚"
    ICO_TAG="🏷️"
    ICO_SKIP="⏭️ "
    ICO_LIST="📋"
    ICO_TELESCOPE="🔭"
    ICO_ROCKET="🚀"
    ICO_LINK="🔗"
    ICO_STOP="🛑"
    ICO_PARTY="🎉"
else
    ICO_OK="[OK]"
    ICO_ERR="[ERROR]"
    ICO_WARN="[WARN]"
    ICO_SEARCH="[1]"
    ICO_PACKAGE="[2]"
    ICO_DOCKER="[3]"
    ICO_HEALTH="[4]"
    ICO_SHELL="[6]"
    ICO_TAG="[5]"
    ICO_SKIP="[SKIP]"
    ICO_LIST="--"
    ICO_TELESCOPE="--"
    ICO_ROCKET=">>"
    ICO_LINK="--"
    ICO_STOP="--"
    ICO_PARTY="--"
fi

# =============================================================================
# Logging utilities
# =============================================================================

info() {
    printf '  %s\n' "$*" >&2
}

warn() {
    printf '  %s%s %s%s\n' "$YELLOW" "$ICO_WARN" "$*" "$RESET" >&2
}

error() {
    printf '  %s%s %s%s\n' "$RED" "$ICO_ERR" "$*" "$RESET" >&2
}

success() {
    printf '  %s%s %s%s\n' "$GREEN" "$ICO_OK" "$*" "$RESET" >&2
}

die() {
    local msg="$1"
    local suggestion="${2:-}"
    error "$msg"
    if [ -n "$suggestion" ]; then
        printf '     %s→ %s%s\n' "$YELLOW" "$suggestion" "$RESET" >&2
    fi
    exit 1
}

step_header() {
    local n="$1"
    local total="$2"
    local emoji="$3"
    local msg="$4"
    printf '\n%s%s Step %s/%s — %s%s\n' "$BOLD" "$emoji" "$n" "$total" "$msg" "$RESET" >&2
}

# =============================================================================
# Spinner (interactive terminals only)
# =============================================================================

SPINNER_PID=""

spinner_start() {
    if [ "$INTERACTIVE" != true ]; then
        return 0
    fi
    local msg="$1"
    (
        local frames='⠋⠙⠹⠸⠼⠴⠦⠧'
        local i=0
        local len=${#frames}
        while true; do
            local frame="${frames:$i:1}"
            printf '\r  %s %s' "$frame" "$msg" >&2
            i=$(( (i + 1) % len ))
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
}

spinner_stop() {
    if [ -n "$SPINNER_PID" ]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
        # Clear the spinner line
        printf '\r\033[K' >&2
    fi
}

# =============================================================================
# Cleanup trap
# =============================================================================

cleanup() {
    spinner_stop
}

trap cleanup EXIT

# =============================================================================
# Argument parsing
# =============================================================================

SHELL_OVERRIDE=""
CUSTOM_RESOURCE_ATTRS=""

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
    step_header 1 "$TOTAL_STEPS" "$ICO_SEARCH" "Checking prerequisites"

    # Bash version (informational — we target 3.2+)
    local bash_major
    bash_major="${BASH_VERSINFO[0]}"
    if [ "$bash_major" -lt 3 ]; then
        die "Bash 3.2+ is required (found $BASH_VERSION)" \
            "Install a newer version of Bash"
    fi

    # Docker
    if ! command -v docker >/dev/null 2>&1; then
        die "Docker is not installed" \
            "Install Docker: https://docs.docker.com/get-docker/"
    fi

    local docker_version
    docker_version="$(docker --version 2>/dev/null | sed 's/Docker version \([^,]*\).*/\1/')"

    if ! docker info >/dev/null 2>&1; then
        die "Docker daemon is not running" \
            "Start Docker Desktop and re-run this script"
    fi
    success "Docker v${docker_version} (daemon running)"

    # Docker Compose v2+
    if ! docker compose version >/dev/null 2>&1; then
        die "Docker Compose v2 plugin not found" \
            "Install Docker Compose v2: https://docs.docker.com/compose/install/"
    fi

    local compose_version
    compose_version="$(docker compose version --short 2>/dev/null || docker compose version 2>/dev/null)"
    compose_version="$(printf '%s' "$compose_version" | sed 's/^v//')"
    # Extract major version number
    local compose_major
    compose_major="$(printf '%s' "$compose_version" | sed 's/\..*//')"
    if [ -n "$compose_major" ] && [ "$compose_major" -lt 2 ] 2>/dev/null; then
        die "Docker Compose v2+ is required (found v${compose_version})" \
            "Upgrade Docker Compose: https://docs.docker.com/compose/install/"
    fi
    success "Docker Compose v${compose_version}"

    # curl or wget (for health checks)
    if command -v curl >/dev/null 2>&1; then
        FETCH_CMD="curl"
        success "curl available"
    elif command -v wget >/dev/null 2>&1; then
        FETCH_CMD="wget"
        success "wget available"
    else
        die "curl or wget is required for health checks" \
            "Install curl: https://curl.se/download.html"
    fi

    # git (needed for auto-clone mode)
    if ! command -v git >/dev/null 2>&1; then
        warn "git is not installed — auto-clone mode will not be available"
        HAS_GIT=false
    else
        success "git available"
        HAS_GIT=true
    fi
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
    step_header 2 "$TOTAL_STEPS" "$ICO_PACKAGE" "Setting up repository"

    # If docker-compose.yml exists in the script's directory, we're running from a clone
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"

    if [ -f "$script_dir/docker-compose.yml" ]; then
        REPO_DIR="$script_dir"
        success "Using existing repository at $REPO_DIR"
        return 0
    fi

    # Auto-clone mode (curl-pipe-bash scenario)
    info "docker-compose.yml not found — entering auto-clone mode"

    if [ "$HAS_GIT" = "false" ]; then
        die "git is required for auto-clone mode but is not installed" \
            "Install git and re-run: https://git-scm.com/downloads"
    fi

    REPO_DIR="$CC_OTEL_DEFAULT_HOME"

    if [ -d "$REPO_DIR/.git" ]; then
        info "Existing clone found at $REPO_DIR — pulling latest"
        spinner_start "Pulling latest changes..."
        git -C "$REPO_DIR" pull --ff-only >> /dev/null 2>&1 || warn "Could not pull latest changes; continuing with existing clone"
        spinner_stop
    else
        spinner_start "Cloning cc-otel to $REPO_DIR..."
        git clone "$CC_OTEL_REPO" "$REPO_DIR" || die "Failed to clone repository"
        spinner_stop
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
    step_header 3 "$TOTAL_STEPS" "$ICO_DOCKER" "Starting observability stack"

    spinner_start "Starting Docker Compose services..."
    docker compose -f "$REPO_DIR/docker-compose.yml" up -d >> /dev/null 2>&1 \
        || { spinner_stop; die "Failed to start Docker Compose stack" \
             "Check logs: docker compose -f $REPO_DIR/docker-compose.yml logs"; }
    spinner_stop

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

# Pretty service name for display (padded for alignment)
pretty_service_name() {
    local service="$1"
    case "$service" in
        otel-collector) printf 'OTel Collector' ;;
        prometheus)     printf 'Prometheus    ' ;;
        loki)           printf 'Loki          ' ;;
        grafana)        printf 'Grafana       ' ;;
        *)              printf '%s' "$service" ;;
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
    step_header 4 "$TOTAL_STEPS" "$ICO_HEALTH" "Checking service health"

    local failed=""
    local service
    for service in $HEALTH_NAMES; do
        local pretty
        pretty="$(pretty_service_name "$service")"
        if poll_service "$service"; then
            printf '  %s%s %s healthy%s\n' "$GREEN" "$ICO_OK" "$pretty" "$RESET" >&2
        else
            printf '  %s%s %s failed (timeout after %ss)%s\n' "$RED" "$ICO_ERR" "$pretty" "$HEALTH_TIMEOUT" "$RESET" >&2
            printf '     %s→ Check logs: docker compose logs %s%s\n' "$YELLOW" "$service" "$RESET" >&2
            failed="$failed $service"
        fi
    done

    if [ -n "$failed" ]; then
        die "Services did not become healthy:$failed"
    fi
}

# =============================================================================
# Custom resource attribute validation
# =============================================================================

validate_attr_key() {
    local key="$1"
    printf '%s' "$key" | grep -qE '^[a-zA-Z_][a-zA-Z0-9_.]*$'
}

validate_attr_value() {
    local val="$1"
    printf '%s' "$val" | grep -qE '^[^ ,]+$'
}

validate_attrs() {
    local input="$1"

    if [ -z "$input" ]; then
        error "Input cannot be empty"
        return 1
    fi

    local remaining="$input"
    while [ -n "$remaining" ]; do
        # Extract the next comma-separated pair
        local pair
        case "$remaining" in
            *,*)
                pair="${remaining%%,*}"
                remaining="${remaining#*,}"
                ;;
            *)
                pair="$remaining"
                remaining=""
                ;;
        esac

        # Check for key=value format
        case "$pair" in
            *=*)
                local key="${pair%%=*}"
                local val="${pair#*=}"
                ;;
            *)
                error "Invalid pair: '$pair' — expected key=value format"
                return 1
                ;;
        esac

        if [ -z "$key" ]; then
            error "Empty key in pair: '$pair'"
            return 1
        fi

        if [ -z "$val" ]; then
            error "Empty value in pair: '$pair'"
            return 1
        fi

        if ! validate_attr_key "$key"; then
            error "Invalid key: '$key' — must match [a-zA-Z_][a-zA-Z0-9_.]*"
            return 1
        fi

        if ! validate_attr_value "$val"; then
            error "Invalid value: '$val' — must not contain spaces or bare commas"
            return 1
        fi
    done

    return 0
}

# =============================================================================
# Custom resource attributes prompt
# =============================================================================

format_attrs_table() {
    local input="$1"

    printf '\n' >&2
    printf '  %s%s Attributes to add:%s\n' "$BOLD" "$ICO_LIST" "$RESET" >&2
    printf '  %-30s %s\n' "KEY" "VALUE" >&2
    printf '  %-30s %s\n' "------------------------------" "------------------------------" >&2

    local remaining="$input"
    while [ -n "$remaining" ]; do
        local pair
        case "$remaining" in
            *,*)
                pair="${remaining%%,*}"
                remaining="${remaining#*,}"
                ;;
            *)
                pair="$remaining"
                remaining=""
                ;;
        esac

        local key="${pair%%=*}"
        local val="${pair#*=}"
        printf '  %-30s %s\n' "$key" "$val" >&2
    done
    printf '\n' >&2
}

prompt_custom_attributes() {
    step_header 5 "$TOTAL_STEPS" "$ICO_TAG" "Custom resource attributes"

    # Non-interactive: skip silently
    if [ "$INTERACTIVE" != true ]; then
        info "Non-interactive mode — skipping custom attributes"
        return 0
    fi

    info "You can tag all your metrics with custom labels (team, department, cost center)."
    info "These get attached to every metric and event automatically."
    printf '\n' >&2
    printf '  Would you like to add custom resource attributes? [y/N] ' >&2
    read -r answer

    case "$answer" in
        y|Y|yes|Yes|YES) ;;
        *)
            info "$ICO_SKIP Skipping custom attributes. You can add them later in your shell profile."
            return 0
            ;;
    esac

    # Show format rules
    printf '\n' >&2
    info "Format: ${BOLD}key=value${RESET} pairs, comma-separated (no spaces around commas)"
    info "  Keys:   letters, digits, underscores, dots (start with letter or underscore)"
    info "  Values: any characters except spaces and bare commas"
    info "  Example: ${BOLD}department=engineering,team.id=platform${RESET}"
    printf '\n' >&2

    # Read/validate loop
    while true; do
        printf '  > ' >&2
        read -r raw_input
        if validate_attrs "$raw_input"; then
            break
        fi
        info "Please try again."
    done

    # Display confirmation table
    format_attrs_table "$raw_input"
    printf '  Look good? [Y/n] ' >&2
    read -r confirm
    case "$confirm" in
        n|N|no|No|NO)
            info "$ICO_SKIP Discarded. You can add attributes later."
            return 0
            ;;
    esac

    # Store in global for generate_profile_block to use
    CUSTOM_RESOURCE_ATTRS="$raw_input"
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
    local attrs="${CUSTOM_RESOURCE_ATTRS:-}"

    case "$shell_name" in
        bash|zsh)
            printf '%s\n' "# >>> cc-otel >>>"
            printf '%s\n' "# Managed by cc-otel installer — do not edit manually"
            printf '%s\n' 'export CLAUDE_CODE_ENABLE_TELEMETRY=1'
            printf '%s\n' 'export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4317"'
            printf '%s\n' 'export OTEL_EXPORTER_OTLP_PROTOCOL="grpc"'
            printf '%s\n' 'export OTEL_METRICS_EXPORTER="otlp"'
            printf '%s\n' 'export OTEL_LOGS_EXPORTER="otlp"'
            if [ -n "$attrs" ]; then
                printf 'export OTEL_RESOURCE_ATTRIBUTES="%s"\n' "$attrs"
            fi
            printf '%s\n' "# <<< cc-otel <<<"
            ;;
        fish)
            printf '%s\n' "# >>> cc-otel >>>"
            printf '%s\n' "# Managed by cc-otel installer — do not edit manually"
            printf '%s\n' 'set -gx CLAUDE_CODE_ENABLE_TELEMETRY 1'
            printf '%s\n' 'set -gx OTEL_EXPORTER_OTLP_ENDPOINT "http://localhost:4317"'
            printf '%s\n' 'set -gx OTEL_EXPORTER_OTLP_PROTOCOL "grpc"'
            printf '%s\n' 'set -gx OTEL_METRICS_EXPORTER "otlp"'
            printf '%s\n' 'set -gx OTEL_LOGS_EXPORTER "otlp"'
            if [ -n "$attrs" ]; then
                printf 'set -gx OTEL_RESOURCE_ATTRIBUTES "%s"\n' "$attrs"
            fi
            printf '%s\n' "# <<< cc-otel <<<"
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
    success "Backup saved to ${profile_path}.cc-otel-backup"

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

    success "Environment variables injected"
}

# =============================================================================
# Welcome banner
# =============================================================================

print_welcome() {
    cat >&2 <<EOF

${BOLD}  ╔══════════════════════════════════════════════════╗
  ║  ${ICO_TELESCOPE} cc-otel — Claude Code Observability         ║
  ║  One-command setup for metrics & dashboards       ║
  ╚══════════════════════════════════════════════════╝${RESET}
EOF
}

# =============================================================================
# Completion banner
# =============================================================================

print_summary() {
    local shell_name="$1"
    local profile_path="$2"

    cat >&2 <<EOF

${BOLD}  ╔══════════════════════════════════════════════════╗
  ║  ${ICO_PARTY} Setup complete!                              ║
  ╚══════════════════════════════════════════════════╝${RESET}

  ${BOLD}Stack status:${RESET}
    ${GREEN}${ICO_OK} OTel Collector${RESET}  http://localhost:13133
    ${GREEN}${ICO_OK} Prometheus${RESET}      http://localhost:9090
    ${GREEN}${ICO_OK} Loki${RESET}            http://localhost:3100
    ${GREEN}${ICO_OK} Grafana${RESET}         http://localhost:3000

  ${BOLD}Shell configuration:${RESET}
    Shell:    ${shell_name}
    Profile:  ${profile_path}
    Backup:   ${profile_path}.cc-otel-backup

  ${BOLD}Next steps:${RESET}
    ${ICO_ROCKET} Restart your shell or run:
         ${BOLD}source ${profile_path}${RESET}
    ${ICO_ROCKET} Start a Claude Code session — telemetry flows automatically
    ${ICO_LINK} Open Grafana: ${BOLD}${BLUE}http://localhost:3000${RESET}

  ${ICO_STOP} To stop the stack:
    ${BOLD}docker compose -f ${REPO_DIR}/docker-compose.yml down${RESET}
EOF
}

# =============================================================================
# Main orchestrator
# =============================================================================

main() {
    parse_args "$@"

    print_welcome

    check_prerequisites
    setup_repo
    launch_stack
    wait_for_services
    prompt_custom_attributes

    # Step 6: Shell configuration
    step_header 6 "$TOTAL_STEPS" "$ICO_SHELL" "Configuring shell environment"

    local shell_name
    shell_name="$(detect_shell)"
    success "Detected shell: $shell_name"

    local profile_path
    profile_path="$(resolve_shell_profile "$shell_name")"
    success "Profile: $profile_path"

    inject_or_update_profile "$profile_path" "$shell_name"

    print_summary "$shell_name" "$profile_path"
}

main "$@"
