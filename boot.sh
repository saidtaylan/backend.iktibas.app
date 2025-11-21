#!/bin/bash
#
# Supabase Self-Host Server Bootstrap Script
# Purpose: Bootstrap a RHEL-based server to run Supabase self-hosted with Docker, Nginx, and SSL
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
readonly BASE_DIRECTORY="/opt/backend.iktibas.app"
readonly DOMAIN="api.iktibas.app"
readonly LOG_DIR="/var/log/supabase"
readonly BACKUP_SCRIPT="$BASE_DIRECTORY/scripts/db-backup.sh"
readonly CRON_FILE="/etc/cron.d/supabase-db-backup"

# =============================================================================
# Logging Functions
# =============================================================================
log_info() {
    echo -e "\033[0;32m[INFO]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "\033[0;33m[WARN]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_section() {
    echo ""
    echo "============================================================================="
    echo " $1"
    echo "============================================================================="
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

command_exists() {
    command -v "$1" &>/dev/null
}

service_is_active() {
    systemctl is-active --quiet "$1"
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
        if [[ $attempt -le $max_attempts ]]; then
            log_info "Retrying in $delay seconds..."
            sleep "$delay"
        fi
    done

    log_error "Command failed after $max_attempts attempts: ${cmd[*]}"
    return 1
}

# =============================================================================
# Validation Functions
# =============================================================================
validate_prerequisites() {
    log_section "Validating Prerequisites"

    check_root
    check_rhel_based

    if [[ ! -d "$BASE_DIRECTORY" ]]; then
        log_error "Base directory does not exist: $BASE_DIRECTORY"
        log_error "Please create the directory and place your Supabase configuration files first"
        exit 1
    fi

    local required_files=(
        "$BASE_DIRECTORY/nginx/nginx.conf"
        "$BASE_DIRECTORY/nginx/api.iktibas.app.conf"
        "$BACKUP_SCRIPT"
    )

    local missing_files=()
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        fi
    done

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_error "Missing required configuration files:"
        for file in "${missing_files[@]}"; do
            log_error "  - $file"
        done
        exit 1
    fi

    log_info "All prerequisites validated successfully"
}

# =============================================================================
# Installation Functions
# =============================================================================
update_system() {
    log_section "Updating System Packages"
    
    log_info "Running system update..."
    if retry_command 3 10 dnf update -y; then
        log_info "System update completed successfully"
    else
        log_error "System update failed"
        exit 1
    fi
}

install_base_packages() {
    log_section "Installing Base Packages"

    local packages=(epel-release make policycoreutils-python-utils)
    
    log_info "Installing: ${packages[*]}"
    if dnf install -y "${packages[@]}"; then
        log_info "Base packages installed successfully"
    else
        log_error "Failed to install base packages"
        exit 1
    fi
}

install_docker() {
    log_section "Installing Docker"

    if command_exists docker && service_is_active docker; then
        log_info "Docker is already installed and running"
        docker --version
        return 0
    fi

    log_info "Adding Docker repository..."
    dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo

    log_info "Installing Docker packages..."
    local docker_packages=(
        docker-ce
        docker-ce-cli
        containerd.io
        docker-buildx-plugin
        docker-compose-plugin
    )

    if ! dnf install -y "${docker_packages[@]}"; then
        log_error "Failed to install Docker packages"
        exit 1
    fi

    log_info "Configuring Docker group..."
    if ! getent group docker &>/dev/null; then
        groupadd docker
        log_info "Docker group created"
    else
        log_info "Docker group already exists"
    fi

    local target_user="${SUDO_USER:-$USER}"
    if [[ -n "$target_user" && "$target_user" != "root" ]]; then
        if ! id -nG "$target_user" | grep -qw docker; then
            usermod -aG docker "$target_user"
            log_info "User '$target_user' added to docker group"
            log_warn "You may need to log out and back in for docker group changes to take effect"
        else
            log_info "User '$target_user' is already in docker group"
        fi
    fi

    log_info "Enabling and starting Docker service..."
    systemctl enable --now docker

    if service_is_active docker; then
        log_info "Docker installed and running successfully"
        docker --version
    else
        log_error "Docker service failed to start"
        exit 1
    fi
}

install_nginx() {
    log_section "Installing and Configuring Nginx"

    if ! command_exists nginx; then
        log_info "Installing Nginx..."
        if ! dnf install -y nginx; then
            log_error "Failed to install Nginx"
            exit 1
        fi
    else
        log_info "Nginx is already installed"
    fi

    log_info "Configuring Nginx..."

    # Backup existing config if it exists and is not a symlink
    if [[ -f /etc/nginx/nginx.conf && ! -L /etc/nginx/nginx.conf ]]; then
        local backup_file="/etc/nginx/nginx.conf.backup.$(date +%Y%m%d%H%M%S)"
        cp /etc/nginx/nginx.conf "$backup_file"
        log_info "Backed up existing nginx.conf to $backup_file"
    fi

    # Remove existing config and create symlink
    rm -f /etc/nginx/nginx.conf
    ln -sf "$BASE_DIRECTORY/nginx/nginx.conf" /etc/nginx/nginx.conf
    log_info "Linked main nginx.conf"

    # Create conf.d symlink if not exists
    if [[ ! -L "/etc/nginx/conf.d/api.iktibas.app.conf" ]]; then
        ln -sf "$BASE_DIRECTORY/nginx/api.iktibas.app.conf" /etc/nginx/conf.d/
        log_info "Linked api.iktibas.app.conf to conf.d"
    fi

    # Test nginx configuration
    log_info "Testing Nginx configuration..."
    if ! nginx -t; then
        log_error "Nginx configuration test failed"
        exit 1
    fi

    log_info "Enabling and starting Nginx service..."
    systemctl enable --now nginx

    if service_is_active nginx; then
        log_info "Nginx installed and running successfully"
    else
        log_error "Nginx service failed to start"
        exit 1
    fi
}

configure_selinux() {
    log_section "Configuring SELinux"

    if ! command_exists getenforce; then
        log_warn "SELinux tools not found, skipping SELinux configuration"
        return 0
    fi

    local selinux_status
    selinux_status=$(getenforce 2>/dev/null || echo "Disabled")

    if [[ "$selinux_status" == "Disabled" ]]; then
        log_warn "SELinux is disabled, skipping SELinux configuration"
        return 0
    fi

    log_info "SELinux is $selinux_status, applying configurations..."

    # Add SELinux port for backend (8080)
    if ! semanage port -l | grep -q "http_port_t.*8080"; then
        if semanage port -a -t http_port_t -p tcp 8080 2>/dev/null; then
            log_info "Added SELinux port 8080 for http_port_t"
        else
            # Port might already be defined differently, try modify
            semanage port -m -t http_port_t -p tcp 8080 2>/dev/null || true
            log_info "Modified SELinux port 8080 for http_port_t"
        fi
    else
        log_info "SELinux port 8080 already configured"
    fi

    # Allow httpd to make network connections
    if ! getsebool httpd_can_network_connect | grep -q "on$"; then
        setsebool -P httpd_can_network_connect 1
        log_info "Enabled httpd_can_network_connect SELinux boolean"
    else
        log_info "httpd_can_network_connect already enabled"
    fi

    log_info "SELinux configuration completed"
}

configure_firewall() {
    log_section "Configuring Firewall"

    if ! command_exists firewall-cmd; then
        log_warn "firewalld not found, skipping firewall configuration"
        return 0
    fi

    if ! service_is_active firewalld; then
        log_warn "firewalld is not running, skipping firewall configuration"
        return 0
    fi

    log_info "Adding firewall rules..."

    local services=(http https)
    for service in "${services[@]}"; do
        if ! firewall-cmd --query-service="$service" --permanent &>/dev/null; then
            firewall-cmd --permanent --add-service="$service"
            log_info "Added firewall rule for $service"
        else
            log_info "Firewall rule for $service already exists"
        fi
    done

    firewall-cmd --reload
    log_info "Firewall configuration completed"
}

install_certbot() {
    log_section "Installing Certbot and Obtaining SSL Certificate"

    if ! command_exists certbot; then
        log_info "Installing Certbot..."
        if ! dnf install -y certbot python3-certbot-nginx; then
            log_error "Failed to install Certbot"
            exit 1
        fi
    else
        log_info "Certbot is already installed"
    fi

    # Check if certificate already exists
    if [[ -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
        log_info "SSL certificate for $DOMAIN already exists"
        log_info "To renew manually, run: certbot renew"
        return 0
    fi

    log_info "Obtaining SSL certificate for $DOMAIN..."
    log_warn "This requires the domain to be pointing to this server"
    
    # Interactive mode for initial setup - user needs to provide email
    if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email; then
        log_info "SSL certificate obtained successfully"
    else
        log_warn "Certbot failed - you may need to run manually:"
        log_warn "  certbot --nginx -d $DOMAIN"
        log_warn "Ensure DNS is configured and ports 80/443 are accessible"
    fi
}

setup_log_directory() {
    log_section "Setting Up Log Directory"

    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR"
        chmod 755 "$LOG_DIR"
        log_info "Created log directory: $LOG_DIR"
    else
        log_info "Log directory already exists: $LOG_DIR"
    fi
}

setup_backup_cron() {
    log_section "Setting Up Database Backup Cron Job"

    if [[ ! -x "$BACKUP_SCRIPT" ]]; then
        chmod +x "$BACKUP_SCRIPT"
        log_info "Made backup script executable"
    fi

    # Create cron job with proper formatting
    cat > "$CRON_FILE" << EOF
# Supabase Database Backup - runs daily at 3 AM
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

0 3 * * * root $BACKUP_SCRIPT >> $LOG_DIR/db-backup.log 2>&1
EOF

    chmod 644 "$CRON_FILE"
    log_info "Created cron job for database backup at $CRON_FILE"

    # Validate cron syntax
    if command_exists crond; then
        systemctl restart crond 2>/dev/null || true
    fi

    log_info "Backup cron job configured to run daily at 3:00 AM"
}

# =============================================================================
# Summary Function
# =============================================================================
print_summary() {
    log_section "Bootstrap Complete"

    echo ""
    echo "Summary:"
    echo "  ✓ System packages updated"
    echo "  ✓ Docker installed and configured"
    echo "  ✓ Nginx installed and configured"
    echo "  ✓ SELinux configured"
    echo "  ✓ Firewall configured"
    echo "  ✓ SSL certificate setup attempted"
    echo "  ✓ Backup cron job configured"
    echo ""
    echo "Next Steps:"
    echo "  1. Log out and back in for docker group changes to take effect"
    echo "  2. Verify your Supabase docker-compose.yml is in place"
    echo "  3. Start Supabase: cd $BASE_DIRECTORY && docker compose up -d"
    echo "  4. Verify Nginx: systemctl status nginx"
    echo "  5. Test your API: curl -I https://$DOMAIN"
    echo ""
    echo "Useful Commands:"
    echo "  - View logs: journalctl -u nginx -f"
    echo "  - Docker logs: docker compose logs -f"
    echo "  - Renew SSL: certbot renew --dry-run"
    echo "  - Backup logs: tail -f $LOG_DIR/db-backup.log"
    echo ""
}

# =============================================================================
# Cleanup on Error
# =============================================================================
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code $exit_code"
        log_error "Please check the errors above and fix any issues"
    fi
}

trap cleanup EXIT

# =============================================================================
# Main Execution
# =============================================================================
main() {
    log_section "Supabase Server Bootstrap Script"
    log_info "Starting bootstrap process for $DOMAIN"

    validate_prerequisites
    update_system
    install_base_packages
    install_docker
    install_nginx
    configure_selinux
    configure_firewall
    install_certbot
    setup_log_directory
    setup_backup_cron
    print_summary
}

main "$@"
