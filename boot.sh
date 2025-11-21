#!/bin/bash
#
# Supabase Self-Host Server Bootstrap Script (Idempotent)
# Purpose: Bootstrap a RHEL-based server to run Supabase self-hosted
# 
# This script is stateless and idempotent - safe to run multiple times.
# Completed steps are automatically detected and skipped.
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
readonly BASE_DIRECTORY="/opt/iktibas/backend.iktibas.app"
readonly DOMAIN="api.iktibas.app"
readonly LOG_DIR="/var/log/supabase"
readonly BACKUP_SCRIPT="$BASE_DIRECTORY/scripts/db-backup.sh"
readonly CRON_FILE="/etc/cron.d/supabase-db-backup"
readonly STATE_DIR="/var/lib/supabase-bootstrap"
readonly STATE_FILE="$STATE_DIR/state"

# =============================================================================
# Logging Functions
# =============================================================================
log_info()    { echo -e "\033[0;32m[INFO]\033[0m    $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_warn()    { echo -e "\033[0;33m[WARN]\033[0m    $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2; }
log_error()   { echo -e "\033[0;31m[ERROR]\033[0m   $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2; }
log_skip()    { echo -e "\033[0;36m[SKIP]\033[0m    $(date '+%Y-%m-%d %H:%M:%S') - $1 (already done)"; }
log_section() { echo -e "\n\033[1;37m=== $1 ===\033[0m"; }

# =============================================================================
# State Management Functions
# =============================================================================
init_state() {
    mkdir -p "$STATE_DIR"
    touch "$STATE_FILE"
}

mark_done() {
    local step="$1"
    if ! grep -qx "$step" "$STATE_FILE" 2>/dev/null; then
        echo "$step" >> "$STATE_FILE"
    fi
}

is_done() {
    local step="$1"
    grep -qx "$step" "$STATE_FILE" 2>/dev/null
}

reset_state() {
    rm -f "$STATE_FILE"
    log_info "State reset. All steps will run on next execution."
}

# =============================================================================
# Check Functions (Stateless Detection)
# =============================================================================
check_system_updated() {
    # Check if updated within last 24 hours
    local marker="/var/lib/supabase-bootstrap/last-update"
    if [[ -f "$marker" ]]; then
        local last_update=$(cat "$marker")
        local now=$(date +%s)
        local diff=$((now - last_update))
        [[ $diff -lt 86400 ]]
    else
        return 1
    fi
}

check_base_packages() {
    rpm -q epel-release make policycoreutils-python-utils &>/dev/null
}

check_docker_installed() {
    command -v docker &>/dev/null && \
    systemctl is-enabled docker &>/dev/null && \
    systemctl is-active docker &>/dev/null
}

check_docker_group() {
    local target_user="${SUDO_USER:-$USER}"
    [[ "$target_user" == "root" ]] || id -nG "$target_user" 2>/dev/null | grep -qw docker
}

check_nginx_installed() {
    command -v nginx &>/dev/null && \
    systemctl is-enabled nginx &>/dev/null
}

check_selinux_port() {
    command -v semanage &>/dev/null && \
    semanage port -l 2>/dev/null | grep -q "http_port_t.*8080"
}

check_selinux_bool() {
    command -v getsebool &>/dev/null && \
    getsebool httpd_can_network_connect 2>/dev/null | grep -q "on$"
}

check_firewall_http() {
    ! systemctl is-active firewalld &>/dev/null || \
    firewall-cmd --query-service=http --permanent &>/dev/null
}

check_firewall_https() {
    ! systemctl is-active firewalld &>/dev/null || \
    firewall-cmd --query-service=https --permanent &>/dev/null
}

check_certbot_installed() {
    command -v certbot &>/dev/null
}

check_ssl_certificate() {
    [[ -d "/etc/letsencrypt/live/$DOMAIN" ]] && \
    [[ -f "/etc/letsencrypt/options-ssl-nginx.conf" ]]
}

check_nginx_configured() {
    [[ -L /etc/nginx/nginx.conf ]] && \
    [[ "$(readlink -f /etc/nginx/nginx.conf)" == "$BASE_DIRECTORY/nginx/nginx.conf" ]] && \
    [[ -L "/etc/nginx/conf.d/api.iktibas.app.conf" ]]
}

check_log_directory() {
    [[ -d "$LOG_DIR" ]]
}

check_backup_cron() {
    [[ -f "$CRON_FILE" ]] && grep -q "$BACKUP_SCRIPT" "$CRON_FILE"
}

# =============================================================================
# Utility Functions
# =============================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

check_rhel_based() {
    if ! command -v dnf &>/dev/null; then
        log_error "This script requires a RHEL-based system with dnf package manager"
        exit 1
    fi
}

retry_command() {
    local max_attempts="${1:-3}"
    local delay="${2:-5}"
    shift 2
    local cmd=("$@")
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if "${cmd[@]}"; then
            return 0
        fi
        log_warn "Command failed (attempt $attempt/$max_attempts): ${cmd[*]}"
        ((attempt++))
        [[ $attempt -le $max_attempts ]] && sleep "$delay"
    done
    return 1
}

# =============================================================================
# Validation
# =============================================================================
validate_prerequisites() {
    log_section "Validating Prerequisites"

    check_root
    check_rhel_based

    if [[ ! -d "$BASE_DIRECTORY" ]]; then
        log_error "Base directory does not exist: $BASE_DIRECTORY"
        exit 1
    fi

    local required_files=(
        "$BASE_DIRECTORY/nginx/nginx.conf"
        "$BASE_DIRECTORY/nginx/api.iktibas.app.conf"
        "$BACKUP_SCRIPT"
    )

    local missing=()
    for f in "${required_files[@]}"; do
        [[ -f "$f" ]] || missing+=("$f")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required files:"
        printf '  - %s\n' "${missing[@]}" >&2
        exit 1
    fi

    init_state
    log_info "Prerequisites validated"
}

# =============================================================================
# Installation Steps (Each is Idempotent)
# =============================================================================
step_system_update() {
    log_section "System Update"
    
    if check_system_updated; then
        log_skip "System update (updated within 24h)"
        return 0
    fi

    log_info "Updating system packages..."
    if retry_command 3 10 dnf update -y; then
        mkdir -p "$STATE_DIR"
        date +%s > "$STATE_DIR/last-update"
        log_info "System update completed"
    else
        log_error "System update failed"
        exit 1
    fi
}

step_base_packages() {
    log_section "Base Packages"

    if check_base_packages; then
        log_skip "Base packages already installed"
        return 0
    fi

    log_info "Installing base packages..."
    dnf install -y epel-release make policycoreutils-python-utils
    log_info "Base packages installed"
}

step_docker() {
    log_section "Docker"

    if check_docker_installed; then
        log_skip "Docker already installed and running"
        docker --version
    else
        log_info "Adding Docker repository..."
        dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo 2>/dev/null || true

        log_info "Installing Docker..."
        dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        log_info "Enabling Docker service..."
        systemctl enable --now docker
        log_info "Docker installed"
        docker --version
    fi

    # Docker group (separate check)
    if check_docker_group; then
        log_skip "Docker group already configured"
    else
        getent group docker &>/dev/null || groupadd docker
        local target_user="${SUDO_USER:-$USER}"
        if [[ -n "$target_user" && "$target_user" != "root" ]]; then
            usermod -aG docker "$target_user"
            log_info "User '$target_user' added to docker group"
            log_warn "Log out and back in for group changes to take effect"
        fi
    fi
}

step_nginx_install() {
    log_section "Nginx Installation"

    if check_nginx_installed; then
        log_skip "Nginx already installed"
        return 0
    fi

    log_info "Installing Nginx..."
    dnf install -y nginx
    systemctl enable nginx
    systemctl start nginx
    log_info "Nginx installed and started with default config"
}

step_selinux() {
    log_section "SELinux Configuration"

    local selinux_status=$(getenforce 2>/dev/null || echo "Disabled")
    if [[ "$selinux_status" == "Disabled" ]]; then
        log_skip "SELinux is disabled"
        return 0
    fi

    # Port 8080
    if check_selinux_port; then
        log_skip "SELinux port 8080 already configured"
    else
        log_info "Adding SELinux port 8080..."
        semanage port -a -t http_port_t -p tcp 8080 2>/dev/null || \
        semanage port -m -t http_port_t -p tcp 8080 2>/dev/null || true
        log_info "SELinux port 8080 configured"
    fi

    # httpd_can_network_connect
    if check_selinux_bool; then
        log_skip "httpd_can_network_connect already enabled"
    else
        log_info "Enabling httpd_can_network_connect..."
        setsebool -P httpd_can_network_connect 1
        log_info "SELinux boolean enabled"
    fi
}

step_firewall() {
    log_section "Firewall Configuration"

    if ! systemctl is-active firewalld &>/dev/null; then
        log_skip "Firewalld is not running"
        return 0
    fi

    local changed=false

    if check_firewall_http; then
        log_skip "Firewall HTTP rule exists"
    else
        firewall-cmd --permanent --add-service=http
        log_info "Added HTTP firewall rule"
        changed=true
    fi

    if check_firewall_https; then
        log_skip "Firewall HTTPS rule exists"
    else
        firewall-cmd --permanent --add-service=https
        log_info "Added HTTPS firewall rule"
        changed=true
    fi

    if $changed; then
        firewall-cmd --reload
        log_info "Firewall reloaded"
    fi
}

step_certbot() {
    log_section "SSL Certificate"

    # Install certbot if needed
    if check_certbot_installed; then
        log_skip "Certbot already installed"
    else
        log_info "Installing Certbot..."
        dnf install -y certbot python3-certbot-nginx
        log_info "Certbot installed"
    fi

    # Get certificate if needed
    if check_ssl_certificate; then
        log_skip "SSL certificate for $DOMAIN already exists"
    else
        log_info "Obtaining SSL certificate for $DOMAIN..."
        if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email; then
            log_info "SSL certificate obtained"
        else
            log_warn "Certbot failed. Run manually: certbot --nginx -d $DOMAIN"
            log_warn "Ensure DNS points to this server and ports 80/443 are open"
        fi
    fi
}

step_nginx_configure() {
    log_section "Nginx Configuration"

    if check_nginx_configured; then
        # Verify config is valid
        if nginx -t 2>/dev/null; then
            log_skip "Nginx already configured correctly"
            return 0
        else
            log_warn "Nginx config invalid, reconfiguring..."
        fi
    fi

    log_info "Configuring Nginx..."

    # Backup if not symlink
    if [[ -f /etc/nginx/nginx.conf && ! -L /etc/nginx/nginx.conf ]]; then
        cp /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.backup.$(date +%Y%m%d%H%M%S)"
        log_info "Backed up existing nginx.conf"
    fi

    rm -f /etc/nginx/nginx.conf
    ln -sf "$BASE_DIRECTORY/nginx/nginx.conf" /etc/nginx/nginx.conf

    rm -f "/etc/nginx/conf.d/api.iktibas.app.conf"
    ln -sf "$BASE_DIRECTORY/nginx/api.iktibas.app.conf" /etc/nginx/conf.d/

    log_info "Testing Nginx configuration..."
    if ! nginx -t; then
        log_error "Nginx configuration test failed"
        log_warn "Fix: Update 'listen 443 ssl http2' to 'listen 443 ssl' + 'http2 on;'"
        exit 1
    fi

    systemctl reload nginx
    log_info "Nginx configured and reloaded"
}

step_log_directory() {
    log_section "Log Directory"

    if check_log_directory; then
        log_skip "Log directory already exists"
        return 0
    fi

    mkdir -p "$LOG_DIR"
    chmod 755 "$LOG_DIR"
    log_info "Created log directory: $LOG_DIR"
}

step_backup_cron() {
    log_section "Backup Cron Job"

    if check_backup_cron; then
        log_skip "Backup cron job already configured"
        return 0
    fi

    [[ -x "$BACKUP_SCRIPT" ]] || chmod +x "$BACKUP_SCRIPT"

    cat > "$CRON_FILE" << EOF
# Supabase Database Backup - runs daily at 3 AM
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 3 * * * root $BACKUP_SCRIPT >> $LOG_DIR/db-backup.log 2>&1
EOF

    chmod 644 "$CRON_FILE"
    log_info "Created backup cron job"
}

# =============================================================================
# Summary
# =============================================================================
print_summary() {
    log_section "Bootstrap Complete"

    echo ""
    echo "Status:"
    check_docker_installed && echo "  ✓ Docker" || echo "  ✗ Docker"
    check_nginx_installed && echo "  ✓ Nginx" || echo "  ✗ Nginx"
    check_ssl_certificate && echo "  ✓ SSL Certificate" || echo "  ✗ SSL Certificate"
    check_nginx_configured && echo "  ✓ Nginx Configured" || echo "  ○ Nginx Config (pending SSL)"
    check_backup_cron && echo "  ✓ Backup Cron" || echo "  ✗ Backup Cron"
    echo ""
    echo "Next Steps:"
    echo "  1. cd $BASE_DIRECTORY && docker compose up -d"
    echo "  2. Test: curl -I https://$DOMAIN"
    echo ""
    echo "Re-run this script anytime - completed steps will be skipped."
    echo ""
}

# =============================================================================
# Cleanup
# =============================================================================
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code $exit_code"
        log_info "Fix the issue and re-run - completed steps will be skipped"
    fi
}

trap cleanup EXIT

# =============================================================================
# Main
# =============================================================================
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Idempotent bootstrap script for Supabase self-hosted server.
Safe to run multiple times - completed steps are automatically skipped.

Options:
  -h, --help      Show this help message
  -s, --status    Show current status only (no changes)
  --reset         Reset state and run all steps fresh

EOF
}

show_status() {
    log_section "Current Status"
    echo ""
    check_system_updated && echo "  ✓ System Updated (24h)" || echo "  ○ System Update needed"
    check_base_packages && echo "  ✓ Base Packages" || echo "  ○ Base Packages needed"
    check_docker_installed && echo "  ✓ Docker Installed" || echo "  ○ Docker needed"
    check_docker_group && echo "  ✓ Docker Group" || echo "  ○ Docker Group needed"
    check_nginx_installed && echo "  ✓ Nginx Installed" || echo "  ○ Nginx needed"
    check_selinux_port && echo "  ✓ SELinux Port 8080" || echo "  ○ SELinux Port needed"
    check_selinux_bool && echo "  ✓ SELinux httpd_can_network_connect" || echo "  ○ SELinux bool needed"
    check_firewall_http && echo "  ✓ Firewall HTTP" || echo "  ○ Firewall HTTP needed"
    check_firewall_https && echo "  ✓ Firewall HTTPS" || echo "  ○ Firewall HTTPS needed"
    check_certbot_installed && echo "  ✓ Certbot Installed" || echo "  ○ Certbot needed"
    check_ssl_certificate && echo "  ✓ SSL Certificate" || echo "  ○ SSL Certificate needed"
    check_nginx_configured && echo "  ✓ Nginx Configured" || echo "  ○ Nginx Config needed"
    check_log_directory && echo "  ✓ Log Directory" || echo "  ○ Log Directory needed"
    check_backup_cron && echo "  ✓ Backup Cron" || echo "  ○ Backup Cron needed"
    echo ""
}

main() {
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -s|--status)
            check_root
            show_status
            exit 0
            ;;
        --reset)
            check_root
            reset_state
            exit 0
            ;;
    esac

    log_section "Supabase Server Bootstrap (Idempotent)"
    log_info "Starting bootstrap for $DOMAIN"

    validate_prerequisites
    step_system_update
    step_base_packages
    step_docker
    step_nginx_install
    step_selinux
    step_firewall
    step_nginx_configure
    step_certbot
    step_log_directory
    step_backup_cron
    print_summary
}

main "$@"
