#!/bin/bash

################################################################################
# Script Name: ubuntu-init-setup.sh
# Description: General-purpose Ubuntu server initialization script for hosting
#              Node.js and Rails applications with Docker. Includes security
#              hardening, user setup, and essential development tools.
# Author: DevOps Team
# Version: 2.0.0
# Usage: sudo ./ubuntu-init-setup.sh
################################################################################

set -euo pipefail
IFS=$'\n\t'

################################################################################
# CONFIGURATION
################################################################################

readonly SCRIPT_VERSION="2.0.0"
readonly USERNAME="andrzej"
readonly NEW_HOSTNAME="webet"
readonly SSH_PORT="2222"
readonly TIMEZONE="Europe/Warsaw"
readonly LOCALE="en_US.UTF-8"
readonly RUBY_VERSION="3.4.4"
readonly NODE_VERSION="20"
readonly SWAP_SIZE="2G"
readonly LOG_FILE="/var/log/server-init-setup.log"

# Derived paths
readonly USER_HOME="/home/${USERNAME}"
readonly USER_SSH_DIR="${USER_HOME}/.ssh"
readonly ROOT_SSH_KEY="/root/.ssh/authorized_keys"

################################################################################
# COLOR DEFINITIONS
################################################################################

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

################################################################################
# LOGGING FUNCTIONS
################################################################################

# Initialize log file
init_log() {
    touch "${LOG_FILE}" 2>/dev/null || true
    chmod 644 "${LOG_FILE}" 2>/dev/null || true
    log_message "INFO" "=== Server Initialization Started at $(date) ==="
}

# Log to file
log_message() {
    local level=$1
    shift
    local message="$*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}" >> "${LOG_FILE}" 2>/dev/null || true
}

# Print colored messages
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${NC} ${message}"
    log_message "SUCCESS" "${message}"
}

print_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} ${message}" >&2
    log_message "ERROR" "${message}"
}

print_warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} ${message}"
    log_message "WARNING" "${message}"
}

print_info() {
    local message="$1"
    echo -e "${BLUE}[INFO]${NC} ${message}"
    log_message "INFO" "${message}"
}

print_step() {
    local step_num=$1
    local step_name=$2
    echo ""
    print_color "${CYAN}" "========================================"
    print_color "${CYAN}" "Step ${step_num}: ${step_name}"
    print_color "${CYAN}" "========================================"
    echo ""
    log_message "STEP" "Step ${step_num}: ${step_name}"
}

# Error handler
error_exit() {
    print_error "$1"
    log_message "FATAL" "$1"
    exit 1
}

################################################################################
# UTILITY FUNCTIONS
################################################################################

# Check if script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root. Please use: sudo $0"
    fi
    print_success "Running as root"
}

# Ask yes/no question
ask_yes_no() {
    local question=$1
    local default=${2:-"n"}

    while true; do
        if [[ "${default}" == "y" ]]; then
            print_color "${YELLOW}" "${question} [Y/n]: "
        else
            print_color "${YELLOW}" "${question} [y/N]: "
        fi
        read -r response

        # Use default if empty
        if [[ -z "${response}" ]]; then
            response="${default}"
        fi

        case "${response}" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) print_warning "Please answer yes or no." ;;
        esac
    done
}

# Create backup of a file
backup_file() {
    local file=$1
    if [[ -f "${file}" ]]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "${file}" "${backup}"
        print_info "Backup created: ${backup}"
        log_message "BACKUP" "${file} -> ${backup}"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Display version of installed software
show_version() {
    local name=$1
    local command=$2
    if command_exists "${command%% *}"; then
        local version
        version=$(eval "${command}" 2>/dev/null || echo "unknown")
        print_success "${name}: ${version}"
    fi
}

################################################################################
# STEP 1: INITIAL SETUP
################################################################################

update_system() {
    print_step "1" "Initial System Setup"

    print_info "Updating package lists..."
    if apt-get update -qq; then
        print_success "Package lists updated"
    else
        error_exit "Failed to update package lists"
    fi

    print_info "Upgrading system packages (this may take a while)..."
    if DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq; then
        print_success "System packages upgraded"
    else
        print_warning "Some packages failed to upgrade"
    fi

    print_info "Installing base dependencies..."
    if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        locales; then
        print_success "Base dependencies installed"
    else
        error_exit "Failed to install base dependencies"
    fi
}

set_timezone() {
    print_info "Setting timezone to ${TIMEZONE}..."

    if [[ -f /usr/share/zoneinfo/${TIMEZONE} ]]; then
        if timedatectl set-timezone "${TIMEZONE}" 2>/dev/null; then
            print_success "Timezone set to ${TIMEZONE}"
        else
            ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
            echo "${TIMEZONE}" > /etc/timezone
            print_success "Timezone set to ${TIMEZONE} (manual method)"
        fi

        print_info "Current time: $(date)"
    else
        print_warning "Timezone ${TIMEZONE} not found, skipping"
    fi
}

configure_locale() {
    print_info "Configuring locale to ${LOCALE}..."

    # Generate locale
    if grep -q "^# ${LOCALE}" /etc/locale.gen 2>/dev/null; then
        sed -i "s/^# ${LOCALE}/${LOCALE}/" /etc/locale.gen
    fi

    if locale-gen "${LOCALE}" &>/dev/null; then
        print_success "Locale ${LOCALE} generated"
    else
        print_warning "Failed to generate locale"
    fi

    # Set as default
    update-locale LANG="${LOCALE}" LC_ALL="${LOCALE}" &>/dev/null || true
    print_success "Locale configured"
}

################################################################################
# STEP 2: USER SETUP
################################################################################

setup_user() {
    print_step "2" "User Setup"

    # Check if user already exists
    if id "${USERNAME}" &>/dev/null; then
        print_warning "User '${USERNAME}' already exists, skipping creation"
    else
        print_info "Creating user '${USERNAME}'..."
        if useradd -m -s /bin/bash "${USERNAME}"; then
            print_success "User '${USERNAME}' created"
        else
            error_exit "Failed to create user '${USERNAME}'"
        fi
    fi

    # Grant sudo privileges
    print_info "Granting sudo privileges to '${USERNAME}'..."
    if groups "${USERNAME}" | grep -q '\bsudo\b'; then
        print_warning "User '${USERNAME}' already has sudo privileges"
    else
        if usermod -aG sudo "${USERNAME}"; then
            print_success "Sudo privileges granted"
        else
            error_exit "Failed to grant sudo privileges"
        fi
    fi

    # Copy SSH keys from root
    if [[ -f "${ROOT_SSH_KEY}" ]]; then
        print_info "Copying SSH keys from root to ${USERNAME}..."

        mkdir -p "${USER_SSH_DIR}"
        cp "${ROOT_SSH_KEY}" "${USER_SSH_DIR}/authorized_keys"

        chmod 700 "${USER_SSH_DIR}"
        chmod 600 "${USER_SSH_DIR}/authorized_keys"
        chown -R "${USERNAME}:${USERNAME}" "${USER_SSH_DIR}"

        print_success "SSH keys configured for ${USERNAME}"
    else
        print_warning "Root SSH keys not found at ${ROOT_SSH_KEY}"
    fi
}

################################################################################
# STEP 3: HOSTNAME SETUP
################################################################################

setup_hostname() {
    print_step "3" "Hostname Configuration"

    local current_hostname
    current_hostname=$(hostname)

    if [[ "${current_hostname}" == "${NEW_HOSTNAME}" ]]; then
        print_warning "Hostname is already set to '${NEW_HOSTNAME}'"
        return 0
    fi

    print_info "Setting hostname to '${NEW_HOSTNAME}'..."

    # Set hostname using hostnamectl
    if command_exists hostnamectl; then
        hostnamectl set-hostname "${NEW_HOSTNAME}" &>/dev/null || true
    fi

    # Update /etc/hostname
    echo "${NEW_HOSTNAME}" > /etc/hostname
    print_success "Updated /etc/hostname"

    # Update /etc/hosts
    print_info "Updating /etc/hosts..."
    backup_file "/etc/hosts"

    # Remove old 127.0.1.1 entry
    sed -i '/^127\.0\.1\.1/d' /etc/hosts

    # Add new hostname entry
    echo "127.0.1.1       ${NEW_HOSTNAME}" >> /etc/hosts

    # Ensure localhost entry exists
    if ! grep -q "^127.0.0.1.*localhost" /etc/hosts; then
        sed -i "1i127.0.0.1       localhost" /etc/hosts
    fi

    print_success "Hostname configured to '${NEW_HOSTNAME}'"
}

################################################################################
# STEP 4: FIREWALL SETUP (EARLY)
################################################################################

# Note: SSH security hardening has been moved to the end of the script
# This is a placeholder step number for clarity

setup_firewall() {
    print_step "4" "Firewall Setup"

    print_info "Setting up UFW firewall..."

    # Install ufw if not present
    if ! command_exists ufw; then
        apt-get install -y -qq ufw
    fi

    # Reset UFW to default
    print_info "Configuring UFW rules..."
    ufw --force reset &>/dev/null || true

    # Default policies
    ufw default deny incoming &>/dev/null
    ufw default allow outgoing &>/dev/null

    # Allow SSH on default port 22 for now (will be changed after SSH hardening at the end)
    ufw allow 22/tcp comment "SSH-temporary" &>/dev/null
    print_success "Allowed SSH on port 22 (temporary - will be changed to ${SSH_PORT} after setup completes)"

    # Pre-allow the new SSH port (will be activated after SSH hardening)
    ufw allow "${SSH_PORT}/tcp" comment "SSH/SCP-new-port" &>/dev/null
    print_success "Pre-allowed SSH/SCP on port ${SSH_PORT} (will be activated at end of setup)"
    print_info "Note: SCP will be enabled via SSH port ${SSH_PORT}"

    # Allow HTTP and HTTPS
    ufw allow 80/tcp comment "HTTP-to-HTTPS-redirect" &>/dev/null
    ufw allow 443/tcp comment "HTTPS" &>/dev/null
    print_success "Allowed HTTP (80) and HTTPS (443)"
    print_info "Note: HTTP port 80 will redirect to HTTPS (443) for secure connections"

    # Enable UFW
    print_info "Enabling UFW..."
    echo "y" | ufw enable &>/dev/null

    print_success "UFW firewall configured and enabled"

    # Show status
    print_info "Firewall status:"
    ufw status numbered | head -20
}

setup_fail2ban() {
    print_info "Installing and configuring fail2ban..."

    if ! command_exists fail2ban-client; then
        apt-get install -y -qq fail2ban
    fi

    # Create local jail configuration
    local jail_local="/etc/fail2ban/jail.local"

    cat > "${jail_local}" << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban

[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200
EOF

    # Enable and start fail2ban
    systemctl enable fail2ban &>/dev/null
    systemctl restart fail2ban &>/dev/null

    print_success "Fail2ban configured for SSH protection"
}

################################################################################
# STEP 5: ESSENTIAL SYSTEM TOOLS
################################################################################

install_essential_tools() {
    print_step "5" "Essential System Tools"

    print_info "Installing essential tools..."

    local packages=(
        git
        curl
        wget
        htop
        vim
        build-essential
        unzip
        tree
        net-tools
        dnsutils
        tcpdump
        telnet
        zip
        bzip2
        gzip
        tar
        ncdu
        jq
        tmux
        screen
    )

    if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${packages[@]}"; then
        print_success "Essential tools installed"
    else
        print_warning "Some tools failed to install"
    fi

    # Show installed versions
    show_version "Git" "git --version"
    show_version "Curl" "curl --version | head -1"
    show_version "Wget" "wget --version | head -1"
}

install_fzf() {
    print_info "Installing fzf (fuzzy finder)..."

    local fzf_dir="${USER_HOME}/.fzf"

    # Check if fzf already installed
    if [[ -d "${fzf_dir}" ]]; then
        print_warning "fzf already installed for ${USERNAME}"
        return 0
    fi

    # Clone fzf repository
    if sudo -u "${USERNAME}" git clone --depth 1 https://github.com/junegunn/fzf.git "${fzf_dir}" &>/dev/null; then
        print_success "fzf repository cloned"
    else
        print_error "Failed to clone fzf repository"
        return 1
    fi

    # Install fzf (auto-completion and key bindings)
    print_info "Installing fzf with key bindings..."
    if sudo -u "${USERNAME}" bash -c "cd ${fzf_dir} && ./install --key-bindings --completion --no-update-rc" &>/dev/null; then
        print_success "fzf installed with key bindings"
    else
        print_error "Failed to install fzf"
        return 1
    fi

    # Configure CTRL+P mapping in .bashrc
    print_info "Configuring CTRL+P mapping for fzf..."
    local bashrc="${USER_HOME}/.bashrc"

    if ! grep -q 'fzf key bindings' "${bashrc}" 2>/dev/null; then
        sudo -u "${USERNAME}" tee -a "${bashrc}" > /dev/null << 'EOF'

# fzf configuration
[ -f ~/.fzf.bash ] && source ~/.fzf.bash

# fzf key bindings - Map CTRL+P to fzf file search
bind '"\C-p": "\C-u\C-afzf\n"'
EOF
        print_success "fzf CTRL+P mapping added to .bashrc"
    else
        print_warning "fzf configuration already exists in .bashrc"
    fi

    print_success "fzf installed and configured"
    print_info "CTRL+P will trigger fuzzy file search after ${USERNAME} logs in"
}

################################################################################
# STEP 6: NODE.JS SETUP
################################################################################

install_nodejs() {
    print_step "6" "Node.js Installation"

    if command_exists node; then
        local current_version
        current_version=$(node --version)
        print_warning "Node.js ${current_version} is already installed"

        if ! ask_yes_no "Reinstall Node.js ${NODE_VERSION}.x?" "n"; then
            return 0
        fi
    fi

    print_info "Installing Node.js ${NODE_VERSION}.x from NodeSource..."

    # Download and install NodeSource repository
    if curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash - &>/dev/null; then
        print_success "NodeSource repository added"
    else
        error_exit "Failed to add NodeSource repository"
    fi

    # Install Node.js
    if apt-get install -y -qq nodejs; then
        print_success "Node.js installed"
    else
        error_exit "Failed to install Node.js"
    fi

    # Verify installation
    show_version "Node.js" "node --version"
    show_version "npm" "npm --version"

    # Install yarn globally
    print_info "Installing Yarn package manager..."
    if npm install -g yarn &>/dev/null; then
        show_version "Yarn" "yarn --version"
    else
        print_warning "Failed to install Yarn"
    fi
}

################################################################################
# STEP 7: RUBY/RAILS SETUP
################################################################################

install_ruby_dependencies() {
    print_info "Installing Ruby build dependencies..."

    local ruby_deps=(
        autoconf
        bison
        build-essential
        libssl-dev
        libyaml-dev
        libreadline-dev
        zlib1g-dev
        libncurses5-dev
        libffi-dev
        libgdbm-dev
        libgdbm-compat-dev
    )

    if apt-get install -y -qq "${ruby_deps[@]}"; then
        print_success "Ruby dependencies installed"
    else
        print_warning "Some Ruby dependencies failed to install"
    fi

    print_info "Verifying all Ruby build dependencies are installed..."
    local missing_deps=()
    for dep in "${ruby_deps[@]}"; do
        if ! dpkg -l | grep -q "^ii.*${dep}"; then
            missing_deps+=("${dep}")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_warning "Missing dependencies: ${missing_deps[*]}"
        print_info "Attempting to install missing dependencies..."
        apt-get install -y -qq "${missing_deps[@]}" || true
    else
        print_success "All Ruby dependencies verified"
    fi
}

install_rbenv() {
    print_step "7" "Ruby/Rails Setup"

    install_ruby_dependencies

    local rbenv_dir="${USER_HOME}/.rbenv"
    local ruby_build_dir="${rbenv_dir}/plugins/ruby-build"

    # Install rbenv for user
    if [[ -d "${rbenv_dir}" ]]; then
        print_warning "rbenv already installed for ${USERNAME}"
    else
        print_info "Installing rbenv for ${USERNAME}..."

        # Clone rbenv
        if sudo -u "${USERNAME}" git clone https://github.com/rbenv/rbenv.git "${rbenv_dir}" &>/dev/null; then
            print_success "rbenv cloned"
        else
            error_exit "Failed to clone rbenv"
        fi

        # Build rbenv
        sudo -u "${USERNAME}" bash -c "cd ${rbenv_dir} && src/configure && make -C src" &>/dev/null || true

        # Add rbenv to bashrc
        local bashrc="${USER_HOME}/.bashrc"
        if ! grep -q 'rbenv init' "${bashrc}" 2>/dev/null; then
            sudo -u "${USERNAME}" tee -a "${bashrc}" > /dev/null << 'EOF'

# rbenv configuration
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - bash)"
EOF
            print_success "rbenv added to .bashrc"
        fi
    fi

    # Install ruby-build plugin
    if [[ -d "${ruby_build_dir}" ]]; then
        print_warning "ruby-build already installed"
    else
        print_info "Installing ruby-build plugin..."

        if sudo -u "${USERNAME}" git clone https://github.com/rbenv/ruby-build.git "${ruby_build_dir}" &>/dev/null; then
            print_success "ruby-build installed"
        else
            error_exit "Failed to install ruby-build"
        fi
    fi

    # Install Ruby version
    print_info "Installing Ruby ${RUBY_VERSION} (this may take 10-15 minutes)..."
    print_info "Please be patient, this is compiling Ruby from source..."

    # Check if Ruby version already installed
    if sudo -u "${USERNAME}" bash -c "source ${USER_HOME}/.bashrc && rbenv versions | grep -q ${RUBY_VERSION}" 2>/dev/null; then
        print_warning "Ruby ${RUBY_VERSION} already installed"
    else
        # Install Ruby and show progress (don't suppress output completely)
        if sudo -u "${USERNAME}" bash -c "source ${USER_HOME}/.bashrc && MAKE_OPTS='-j 12' rbenv install ${RUBY_VERSION}" 2>&1 | tee -a "$LOG_FILE"; then
            print_success "Ruby ${RUBY_VERSION} installed successfully"
        else
            print_error "Failed to install Ruby ${RUBY_VERSION}"
            print_info "Check the log at: /tmp/ruby-build.*.log"
            print_info "You can install it manually later with: su - ${USERNAME} -c 'rbenv install ${RUBY_VERSION}'"
            # Don't fail the script, continue
        fi
    fi

    # Set global Ruby version
    print_info "Setting Ruby ${RUBY_VERSION} as global default..."
    sudo -u "${USERNAME}" bash -c "source ${USER_HOME}/.bashrc && rbenv global ${RUBY_VERSION}" &>/dev/null || true
    sudo -u "${USERNAME}" bash -c "source ${USER_HOME}/.bashrc && rbenv rehash" &>/dev/null || true

    # Install bundler and rails
    print_info "Installing bundler and rails gems..."
    sudo -u "${USERNAME}" bash -c "source ${USER_HOME}/.bashrc && gem install bundler rails --no-document" &>/dev/null || true

    print_success "Ruby/Rails setup completed"
    print_info "Ruby version will be available after ${USERNAME} logs in or sources .bashrc"
}

################################################################################
# STEP 8: DATABASE SETUP
################################################################################

install_databases() {
    print_step "8" "Database Installation"

    # PostgreSQL
    print_info "Installing PostgreSQL..."

    if command_exists psql; then
        print_warning "PostgreSQL already installed"
    else
        if apt-get install -y -qq postgresql postgresql-contrib libpq-dev; then
            print_success "PostgreSQL installed"

            # Start and enable service
            systemctl enable postgresql &>/dev/null
            systemctl start postgresql &>/dev/null

            # Create PostgreSQL user for andrzej
            print_info "Creating PostgreSQL user for ${USERNAME}..."
            sudo -u postgres createuser -s "${USERNAME}" 2>/dev/null || print_warning "PostgreSQL user already exists"

            # Create read-only user for database backups
            print_info "Creating read-only PostgreSQL user for database backups..."
            local readonly_user="readonly_user"
            local readonly_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

            # Create user
            sudo -u postgres psql <<SQL 2>/dev/null || print_warning "Read-only user may already exist"
-- Create read-only user
CREATE USER ${readonly_user} WITH PASSWORD '${readonly_password}';
SQL

            # Get all databases and grant permissions
            local databases=$(sudo -u postgres psql -t -c "SELECT datname FROM pg_database WHERE datname NOT IN ('postgres', 'template0', 'template1');")

            for db in $databases; do
                sudo -u postgres psql -d "$db" <<SQL 2>/dev/null || true
-- Grant permissions on database
GRANT CONNECT ON DATABASE "$db" TO ${readonly_user};

-- Grant permissions on schemas and tables
DO \$\$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('pg_catalog', 'information_schema')
    LOOP
        EXECUTE 'GRANT USAGE ON SCHEMA ' || quote_ident(r.schema_name) || ' TO ${readonly_user}';
        EXECUTE 'GRANT SELECT ON ALL TABLES IN SCHEMA ' || quote_ident(r.schema_name) || ' TO ${readonly_user}';
        EXECUTE 'GRANT SELECT ON ALL SEQUENCES IN SCHEMA ' || quote_ident(r.schema_name) || ' TO ${readonly_user}';
        EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA ' || quote_ident(r.schema_name) || ' GRANT SELECT ON TABLES TO ${readonly_user}';
        EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA ' || quote_ident(r.schema_name) || ' GRANT SELECT ON SEQUENCES TO ${readonly_user}';
    END LOOP;
END \$\$;
SQL
            done

            print_success "Read-only PostgreSQL user '${readonly_user}' created"
            print_info "Password for ${readonly_user}: ${readonly_password}"
            log_message "INFO" "Read-only PostgreSQL user created with password: ${readonly_password}"

            show_version "PostgreSQL" "psql --version"
        else
            print_warning "Failed to install PostgreSQL"
        fi
    fi

    # Redis 8 from official repository
    print_info "Installing Redis 8 from official repository..."

    if command_exists redis-server; then
        print_warning "Redis already installed"
        show_version "Redis" "redis-server --version"

        if ! ask_yes_no "Upgrade to Redis 8 from official repository?" "n"; then
            return 0
        fi
    fi

    # Install prerequisites for Redis repository
    print_info "Installing prerequisites..."
    apt-get install -y -qq lsb-release curl gpg

    # Add Redis GPG key
    print_info "Adding Redis GPG key..."
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    chmod 644 /usr/share/keyrings/redis-archive-keyring.gpg

    # Add Redis repository
    print_info "Adding Redis repository..."
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list

    # Update package list
    print_info "Updating package list..."
    apt-get update -qq

    # Install Redis
    if apt-get install -y -qq redis; then
        print_success "Redis 8 installed"

        # Start and enable service
        systemctl enable redis-server &>/dev/null
        systemctl start redis-server &>/dev/null

        show_version "Redis" "redis-server --version"
    else
        print_warning "Failed to install Redis 8"
        return 1
    fi

    # Configure Redis using template
    print_info "Deploying Redis configuration from template..."

    local redis_conf="/etc/redis/redis.conf"
    local template_conf="${SCRIPT_DIR}/common/templates/redis.conf"

    if [ ! -f "$template_conf" ]; then
        print_warning "Redis config template not found: $template_conf"
        print_warning "Skipping Redis configuration"
        return 0
    fi

    # Backup existing config
    if [ -f "$redis_conf" ]; then
        cp "$redis_conf" "${redis_conf}.backup-$(date +%Y%m%d-%H%M%S)"
        print_info "Backed up existing config"
    fi

    # Deploy clean config from template
    cp "$template_conf" "$redis_conf"
    chown redis:redis "$redis_conf"
    chmod 640 "$redis_conf"

    # Test configuration
    if redis-server "$redis_conf" --test-memory 1 2>&1 | grep -q "Configuration passed"; then
        print_success "Configuration syntax is valid"
    else
        print_warning "Configuration test failed, check manually"
    fi

    # Restart Redis to apply configuration
    print_info "Restarting Redis with new configuration..."
    systemctl restart redis-server
    sleep 3

    if redis-cli ping > /dev/null 2>&1; then
        print_success "Redis 8 configured for Streams"
    else
        print_warning "Redis may need manual verification"
    fi
}

################################################################################
# STEP 9: DOCKER SETUP
################################################################################

install_docker() {
    print_step "9" "Docker Installation"

    if command_exists docker; then
        print_warning "Docker already installed"
        show_version "Docker" "docker --version"

        if ! ask_yes_no "Reinstall Docker?" "n"; then
            return 0
        fi
    fi

    print_info "Installing Docker from official repository..."

    # Remove old versions
    apt-get remove -y -qq docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Install prerequisites
    apt-get install -y -qq \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Add Docker's official GPG key
    print_info "Adding Docker GPG key..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg &>/dev/null

    # Set up the repository
    print_info "Adding Docker repository..."
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    apt-get update -qq
    if apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        print_success "Docker installed"
    else
        error_exit "Failed to install Docker"
    fi

    # Add user to docker group
    print_info "Adding ${USERNAME} to docker group..."
    usermod -aG docker "${USERNAME}"
    print_success "${USERNAME} added to docker group"

    # Enable and start Docker
    systemctl enable docker &>/dev/null
    systemctl start docker &>/dev/null

    # Verify installation
    show_version "Docker" "docker --version"
    show_version "Docker Compose" "docker compose version"

    print_success "Docker setup completed"
    print_warning "User ${USERNAME} needs to log out and back in for docker group to take effect"
}

################################################################################
# STEP 10: NGINX SETUP
################################################################################

install_nginx() {
    print_step "10" "Nginx Installation"

    if command_exists nginx; then
        print_warning "Nginx already installed"
        show_version "Nginx" "nginx -v 2>&1"
    else
        print_info "Installing Nginx..."

        if apt-get install -y -qq nginx; then
            print_success "Nginx installed"
        else
            error_exit "Failed to install Nginx"
        fi

        # Enable and start Nginx
        systemctl enable nginx &>/dev/null
        systemctl start nginx &>/dev/null
        show_version "Nginx" "nginx -v 2>&1"
    fi

    # Create directory structure for webet.pl
    print_info "Creating directory structure for webet.pl..."
    mkdir -p /var/www/webet.pl/html
    print_success "Directory /var/www/webet.pl/html created"

    # Create basic HTML file
    print_info "Creating index.html..."
    cat > /var/www/webet.pl/html/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Webet.pl</title>
</head>
<body>
    <h1>Hello World!</h1>
    <p>Welcome to webet.pl</p>
</body>
</html>
EOF

    # Set proper permissions
    chown -R www-data:www-data /var/www/webet.pl
    chmod -R 755 /var/www/webet.pl
    print_success "Created index.html with proper permissions (www-data:www-data)"

    # Create Nginx server block for webet.pl (HTTP-only initially)
    print_info "Creating initial HTTP-only Nginx server block for webet.pl..."
    local webet_conf="/etc/nginx/sites-available/webet.pl"

    cat > "${webet_conf}" << 'EOF'
# HTTP server - Initial configuration (Certbot will modify this to add SSL)
server {
    listen 80;
    listen [::]:80;

    server_name webet.pl www.webet.pl;

    root /var/www/webet.pl/html;
    index index.html index.htm;

    # Security headers (non-SSL)
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    location / {
        try_files $uri $uri/ =404;
    }

    # Deny access to hidden files
    location ~ /\. {
        deny all;
    }
}
EOF

    print_success "Nginx server block created: ${webet_conf}"

    # Remove default nginx site if it exists
    if [[ -L /etc/nginx/sites-enabled/default ]]; then
        print_info "Removing default nginx site..."
        rm -f /etc/nginx/sites-enabled/default
        print_success "Default site removed"
    fi

    # Enable webet.pl site
    if [[ ! -L /etc/nginx/sites-enabled/webet.pl ]]; then
        print_info "Enabling webet.pl site..."
        ln -s /etc/nginx/sites-available/webet.pl /etc/nginx/sites-enabled/
        print_success "webet.pl site enabled"
    else
        print_warning "webet.pl site already enabled"
    fi

    # Test nginx configuration
    print_info "Testing Nginx configuration..."
    if nginx -t &>/dev/null; then
        print_success "Nginx configuration is valid"

        print_info "Reloading Nginx..."
        systemctl reload nginx &>/dev/null
        print_success "Nginx reloaded successfully"
        echo ""
        print_info "Site is accessible at http://webet.pl (HTTP only until SSL is configured)"
        print_info "Certbot will automatically configure HTTPS and HTTP-to-HTTPS redirect later"
    else
        print_error "Nginx configuration test failed!"
        nginx -t
    fi
}

################################################################################
# STEP 11: LET'S ENCRYPT SSL SETUP
################################################################################

setup_letsencrypt() {
    print_step "11" "Let's Encrypt SSL Setup"

    # Install Certbot
    print_info "Installing Certbot and Nginx plugin..."
    if command_exists certbot; then
        print_warning "Certbot already installed"
        show_version "Certbot" "certbot --version"
    else
        if apt-get install -y -qq certbot python3-certbot-nginx; then
            print_success "Certbot and python3-certbot-nginx installed"
            show_version "Certbot" "certbot --version"
        else
            error_exit "Failed to install Certbot"
        fi
    fi

    # Ask user if they want to obtain SSL certificate
    echo ""
    print_color "${YELLOW}" "================================================================================"
    print_color "${YELLOW}" "                    Let's Encrypt SSL Certificate Setup"
    print_color "${YELLOW}" "================================================================================"
    echo ""
    print_color "${RED}" "IMPORTANT: Before proceeding, ensure that:"
    echo ""
    echo "  1. DNS A records for webet.pl and www.webet.pl point to this server's IP"
    echo "  2. Port 80 (HTTP) is accessible from the internet"
    echo "  3. This server is reachable at webet.pl and www.webet.pl"
    echo ""
    print_color "${YELLOW}" "You can verify DNS with:"
    print_color "${CYAN}" "  dig webet.pl +short"
    print_color "${CYAN}" "  dig www.webet.pl +short"
    echo ""
    print_color "${YELLOW}" "NOTE: Currently nginx is serving HTTP-only on port 80."
    print_color "${YELLOW}" "      After SSL setup, Certbot will configure HTTPS and redirect HTTP to HTTPS."
    print_color "${YELLOW}" "================================================================================"
    echo ""

    if ! ask_yes_no "Do you want to obtain Let's Encrypt SSL certificate for webet.pl and www.webet.pl?" "n"; then
        print_info "Skipping SSL certificate setup"
        print_warning "Site will remain HTTP-only (accessible at http://webet.pl)"
        print_info "You can run this command later to obtain SSL certificate and enable HTTPS:"
        print_color "${CYAN}" "  sudo certbot --nginx -d webet.pl -d www.webet.pl --email admin@webet.pl"
        print_info "After running certbot, the site will automatically redirect HTTP to HTTPS"
        return 0
    fi

    # Obtain SSL Certificate
    print_info "Obtaining SSL certificate for webet.pl and www.webet.pl..."
    echo ""
    print_color "${YELLOW}" "This process will:"
    echo "  - Verify domain ownership via HTTP challenge"
    echo "  - Obtain SSL certificate from Let's Encrypt"
    echo "  - Automatically configure Nginx with SSL certificates"
    echo "  - Set up HTTP to HTTPS redirect (HTTPS-only mode)"
    echo ""

    local certbot_output
    if certbot_output=$(certbot --nginx \
        -d webet.pl \
        -d www.webet.pl \
        --non-interactive \
        --agree-tos \
        --email admin@webet.pl 2>&1); then

        print_success "SSL certificate obtained and configured successfully!"
        echo ""
        print_info "Certbot has automatically configured your nginx server with:"
        echo "  - HTTPS server block (port 443) with SSL certificates"
        echo "  - HTTP-to-HTTPS redirect (all HTTP traffic now redirects to HTTPS)"
        print_success "Site is now HTTPS-only and accessible at https://webet.pl"
    else
        print_error "Failed to obtain SSL certificate"
        echo ""
        print_warning "Certbot output:"
        echo "${certbot_output}"
        echo ""
        print_info "Common issues:"
        echo "  - DNS records not pointing to this server"
        echo "  - Port 80 not accessible from internet"
        echo "  - Domain not reachable"
        echo ""
        print_info "You can try again later with:"
        print_color "${CYAN}" "  sudo certbot --nginx -d webet.pl -d www.webet.pl --email admin@webet.pl"
        return 1
    fi

    # Setup Auto-Renewal
    print_info "Setting up automatic certificate renewal..."

    # Certbot automatically installs systemd timer
    if systemctl is-active --quiet certbot.timer; then
        print_success "Certbot renewal timer is already active"
    else
        systemctl enable certbot.timer &>/dev/null
        systemctl start certbot.timer &>/dev/null
        print_success "Certbot renewal timer enabled and started"
    fi

    # Test the renewal process
    print_info "Testing certificate renewal process (dry-run)..."
    if certbot renew --dry-run &>/dev/null; then
        print_success "Certificate renewal test passed"
    else
        print_warning "Certificate renewal test failed (this may be a false alarm)"
    fi

    # Verify the timer is active
    print_info "Certbot renewal timer status:"
    local timer_status
    timer_status=$(systemctl list-timers certbot.timer --no-pager --no-legend 2>/dev/null | head -1)
    if [[ -n "${timer_status}" ]]; then
        echo "  ${timer_status}"
        print_success "Auto-renewal timer is configured"
        print_info "Certbot will automatically check for renewal twice daily"
        print_info "Certificates will be renewed when they have 30 days or less before expiry"
    else
        print_warning "Could not verify timer status"
    fi

    # Create renewal hook to reload Nginx
    print_info "Creating renewal hook to reload Nginx after certificate renewal..."
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy

    cat > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh << 'EOF'
#!/bin/bash
# Reload Nginx after successful certificate renewal
systemctl reload nginx
EOF

    chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
    print_success "Renewal hook created: /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh"
    print_info "Nginx will automatically reload when certificates are renewed"

    # Display certificate information
    echo ""
    print_color "${GREEN}" "================================================================================"
    print_color "${GREEN}" "                    SSL Certificate Information"
    print_color "${GREEN}" "================================================================================"
    echo ""

    if [[ -f /etc/letsencrypt/live/webet.pl/fullchain.pem ]]; then
        # Get certificate expiry date
        local expiry_date
        expiry_date=$(openssl x509 -in /etc/letsencrypt/live/webet.pl/fullchain.pem -noout -enddate 2>/dev/null | cut -d= -f2)

        print_color "${CYAN}" "Certificate Details:"
        echo "  Domains: webet.pl, www.webet.pl"
        echo "  Certificate: /etc/letsencrypt/live/webet.pl/fullchain.pem"
        echo "  Private Key: /etc/letsencrypt/live/webet.pl/privkey.pem"
        echo "  Expires: ${expiry_date}"
        echo ""

        print_color "${CYAN}" "Auto-Renewal:"
        echo "  Status: ENABLED"
        echo "  Check Schedule: Twice daily (systemd timer)"
        echo "  Renewal Window: 30 days before expiry"
        echo "  Post-Renewal: Nginx will automatically reload"
        echo ""

        print_color "${CYAN}" "Access Your Site:"
        print_color "${GREEN}" "  https://webet.pl"
        print_color "${GREEN}" "  https://www.webet.pl"
        echo ""
        print_info "HTTP requests automatically redirect to HTTPS (HTTPS-only mode)"

    else
        print_warning "Certificate files not found (may not have been issued)"
    fi

    print_color "${GREEN}" "================================================================================"
    echo ""

    print_success "Let's Encrypt SSL setup completed successfully!"
}

################################################################################
# STEP 12: RUBY/RAILS LIBRARIES
################################################################################

install_rails_libraries() {
    print_step "12" "Ruby/Rails Development Libraries"

    print_info "Installing libraries for Rails development..."

    local rails_libs=(
        libpq-dev
        libxml2-dev
        libxslt1-dev
        libreadline-dev
        zlib1g-dev
        libssl-dev
        libffi-dev
        libyaml-dev
        imagemagick
        libmagickwand-dev
        libsqlite3-dev
        libcurl4-openssl-dev
    )

    if apt-get install -y -qq "${rails_libs[@]}"; then
        print_success "Rails libraries installed"
    else
        print_warning "Some Rails libraries failed to install"
    fi

    print_info "Installed libraries:"
    echo "  - libpq-dev (PostgreSQL)"
    echo "  - libxml2-dev, libxslt1-dev (Nokogiri)"
    echo "  - imagemagick, libmagickwand-dev (Image processing)"
    echo "  - libreadline-dev, zlib1g-dev, libssl-dev, libffi-dev, libyaml-dev"
}

################################################################################
# STEP 13: GITHUB SSH KEY SETUP
################################################################################

setup_github_ssh() {
    print_step "13" "GitHub SSH Key Setup"

    if ! ask_yes_no "Generate SSH key for GitHub?" "y"; then
        print_info "Skipping GitHub SSH key generation"
        return 0
    fi

    local ssh_key_file="${USER_SSH_DIR}/id_ed25519"
    local email="andrzej@webet.com"

    # Create .ssh directory if needed
    mkdir -p "${USER_SSH_DIR}"
    chmod 700 "${USER_SSH_DIR}"

    # Check if key exists
    if [[ -f "${ssh_key_file}" ]]; then
        print_warning "SSH key already exists at ${ssh_key_file}"

        if ! ask_yes_no "Generate new SSH key (will overwrite existing)?" "n"; then
            print_info "Using existing SSH key"

            if [[ -f "${ssh_key_file}.pub" ]]; then
                display_github_key "${ssh_key_file}.pub"
            fi
            return 0
        fi
    fi

    # Generate SSH key
    print_info "Generating ED25519 SSH key for GitHub..."

    if sudo -u "${USERNAME}" ssh-keygen -t ed25519 -C "${email}" -f "${ssh_key_file}" -N '' &>/dev/null; then
        print_success "SSH key generated"
    else
        error_exit "Failed to generate SSH key"
    fi

    # Set permissions
    chmod 600 "${ssh_key_file}"
    chmod 644 "${ssh_key_file}.pub"
    chown "${USERNAME}:${USERNAME}" "${ssh_key_file}" "${ssh_key_file}.pub"

    # Create SSH config for GitHub
    create_github_config

    # Display public key
    display_github_key "${ssh_key_file}.pub"

    # Test connection
    test_github_connection
}

create_github_config() {
    local ssh_config="${USER_SSH_DIR}/config"

    print_info "Creating SSH config for GitHub..."

    local github_config="Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes"

    # Check if config exists
    if [[ -f "${ssh_config}" ]] && grep -q "Host github.com" "${ssh_config}"; then
        print_warning "GitHub config already exists in ${ssh_config}"
    else
        echo "" >> "${ssh_config}"
        echo "${github_config}" >> "${ssh_config}"
        chmod 600 "${ssh_config}"
        chown "${USERNAME}:${USERNAME}" "${ssh_config}"
        print_success "GitHub SSH config created"
    fi
}

display_github_key() {
    local pub_key_file=$1

    if [[ ! -f "${pub_key_file}" ]]; then
        print_error "Public key file not found: ${pub_key_file}"
        return 1
    fi

    local pub_key
    pub_key=$(cat "${pub_key_file}")

    echo ""
    print_color "${GREEN}" "================================================================================"
    print_color "${GREEN}" "                         GitHub SSH Public Key"
    print_color "${GREEN}" "================================================================================"
    echo ""
    print_color "${CYAN}" "Add this key to your GitHub account:"
    print_color "${CYAN}" "https://github.com/settings/keys"
    echo ""
    print_color "${GREEN}" "-------------------------------------------------------------------------------"
    echo ""
    print_color "${YELLOW}" "${pub_key}"
    echo ""
    print_color "${GREEN}" "================================================================================"
    echo ""
}

test_github_connection() {
    if ask_yes_no "Test GitHub SSH connection now?" "n"; then
        print_info "Testing GitHub connection..."
        print_warning "Type 'yes' if asked about fingerprint authenticity"
        echo ""

        local test_output
        if test_output=$(sudo -u "${USERNAME}" ssh -T git@github.com 2>&1); then
            echo "${test_output}"
        else
            if echo "${test_output}" | grep -q "successfully authenticated"; then
                print_success "GitHub SSH connection successful!"
            else
                print_warning "GitHub connection test output:"
                echo "${test_output}"
            fi
        fi
    else
        print_info "To test GitHub connection later, run as ${USERNAME}:"
        print_info "  ssh -T git@github.com"
    fi
}

################################################################################
# STEP 14: SYSTEM OPTIMIZATION
################################################################################

system_optimization() {
    print_step "14" "System Optimization"

    # Configure swap
    configure_swap

    # Set swappiness
    print_info "Setting swappiness to 10..."
    sysctl vm.swappiness=10 &>/dev/null

    if ! grep -q "vm.swappiness" /etc/sysctl.conf 2>/dev/null; then
        echo "vm.swappiness=10" >> /etc/sysctl.conf
        print_success "Swappiness set to 10 (persistent)"
    fi

    # Configure system limits
    print_info "Configuring system limits (file descriptors)..."

    local limits_conf="/etc/security/limits.conf"
    backup_file "${limits_conf}"

    if ! grep -q "nofile" "${limits_conf}"; then
        cat >> "${limits_conf}" << EOF

# Increased file descriptor limits
*               soft    nofile          65536
*               hard    nofile          65536
root            soft    nofile          65536
root            hard    nofile          65536
EOF
        print_success "File descriptor limits increased"
    fi

    # Enable automatic security updates
    if ask_yes_no "Enable automatic security updates?" "y"; then
        print_info "Installing unattended-upgrades..."

        if apt-get install -y -qq unattended-upgrades apt-listchanges; then
            dpkg-reconfigure -plow unattended-upgrades &>/dev/null || true
            print_success "Automatic security updates enabled"
        else
            print_warning "Failed to install unattended-upgrades"
        fi
    fi
}

configure_swap() {
    print_info "Configuring swap file (${SWAP_SIZE})..."

    # Check if swap already exists
    if swapon --show | grep -q "/swapfile"; then
        local current_size
        current_size=$(swapon --show | grep "/swapfile" | awk '{print $3}')
        print_warning "Swap file already exists (${current_size})"
        return 0
    fi

    # Create swap file
    print_info "Creating ${SWAP_SIZE} swap file..."

    if fallocate -l "${SWAP_SIZE}" /swapfile &>/dev/null; then
        chmod 600 /swapfile
        mkswap /swapfile &>/dev/null
        swapon /swapfile &>/dev/null

        # Make swap persistent
        if ! grep -q "/swapfile" /etc/fstab; then
            echo "/swapfile none swap sw 0 0" >> /etc/fstab
        fi

        print_success "Swap file created and enabled"
    else
        print_warning "Failed to create swap file"
    fi
}

################################################################################
# STEP 15: CRON SETUP
################################################################################

setup_cron() {
    print_step "15" "Cron Configuration"

    # Install cron if not present
    if ! command_exists crontab; then
        print_info "Installing cron..."
        apt-get install -y -qq cron
    fi

    # Enable and start cron service
    systemctl enable cron &>/dev/null
    systemctl start cron &>/dev/null

    print_success "Cron service enabled and running"

    # Setup log rotation for custom logs
    print_info "Configuring log rotation..."

    cat > /etc/logrotate.d/server-init << 'EOF'
/var/log/server-init-setup.log {
    weekly
    rotate 12
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
EOF

    print_success "Log rotation configured"
}

################################################################################
# STEP 16: SSH SECURITY HARDENING (FINAL STEP)
################################################################################

apply_ssh_security() {
    print_step "16" "SSH Security Hardening (Final Step)"

    local sshd_config="/etc/ssh/sshd_config"

    if [[ ! -f "${sshd_config}" ]]; then
        print_warning "SSH config not found at ${sshd_config}, skipping SSH hardening"
        return 0
    fi

    echo ""
    print_color "${CYAN}" "========================================"
    print_color "${CYAN}" "Final Step: Apply SSH Security Changes"
    print_color "${CYAN}" "========================================"
    echo ""

    print_color "${YELLOW}" "About to apply the following SSH security changes:"
    echo ""
    echo "  - Disable password authentication (SSH keys only)"
    echo "  - Disable root login via SSH"
    echo "  - Change SSH port from 22 to ${SSH_PORT}"
    echo "  - Close port 22 on firewall (keep only ${SSH_PORT})"
    echo ""

    print_color "${RED}" "CRITICAL: This will change how you connect to this server!"
    echo ""
    print_color "${YELLOW}" "Current SSH connection:"
    print_color "${CYAN}" "  ssh root@your-server-ip"
    echo ""
    print_color "${YELLOW}" "New SSH connection will be:"
    print_color "${GREEN}" "  ssh -p ${SSH_PORT} ${USERNAME}@your-server-ip"
    echo ""

    print_color "${RED}" "IMPORTANT: Before proceeding, you should:"
    echo ""
    echo "  1. Ensure SSH keys are properly configured for user '${USERNAME}'"
    echo "  2. Test that you can access this server in another terminal"
    echo "  3. Keep this terminal session open until you verify SSH works"
    echo ""

    print_color "${YELLOW}" "================================================================================"
    echo ""

    # Ask for confirmation with default to skip for safety
    if ! ask_yes_no "Ready to apply SSH security changes NOW?" "n"; then
        print_warning "SSH security changes SKIPPED"
        echo ""
        print_info "Your server is still accessible via:"
        print_color "${CYAN}" "  ssh root@your-server-ip"
        echo ""
        print_info "You can apply SSH hardening manually later by:"
        echo "  1. Editing: /etc/ssh/sshd_config"
        echo "  2. Setting: PasswordAuthentication no"
        echo "  3. Setting: PermitRootLogin no"
        echo "  4. Setting: Port ${SSH_PORT}"
        echo "  5. Testing config: sshd -t"
        echo "  6. Restarting SSH: systemctl restart sshd"
        echo "  7. Updating firewall: ufw delete allow 22/tcp && ufw reload"
        echo ""
        return 0
    fi

    echo ""
    print_info "Applying SSH security hardening..."

    # Create backup of SSH config
    backup_file "${sshd_config}"

    # Store whether changes were made
    local changes_applied=false
    local disable_password=false
    local disable_root=false
    local change_port=false

    # Disable password authentication
    print_info "Disabling password authentication (SSH keys only)..."
    sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' "${sshd_config}"
    sed -i 's/^#*ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' "${sshd_config}"
    disable_password=true
    print_success "Password authentication disabled"

    # Disable root login
    print_info "Disabling root login via SSH..."
    sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' "${sshd_config}"
    disable_root=true
    print_success "Root login disabled"

    # Change SSH port
    print_info "Changing SSH port to ${SSH_PORT}..."
    sed -i "s/^#*Port .*/Port ${SSH_PORT}/" "${sshd_config}"
    change_port=true
    print_success "SSH port configured to ${SSH_PORT}"

    # Additional SSH hardening
    print_info "Applying additional SSH security settings..."
    grep -q "^PubkeyAuthentication" "${sshd_config}" || echo "PubkeyAuthentication yes" >> "${sshd_config}"
    grep -q "^PermitEmptyPasswords" "${sshd_config}" || echo "PermitEmptyPasswords no" >> "${sshd_config}"
    grep -q "^X11Forwarding" "${sshd_config}" || echo "X11Forwarding no" >> "${sshd_config}"
    print_success "Additional security settings applied"

    # Test SSH configuration
    print_info "Validating SSH configuration..."
    if sshd -t 2>/dev/null; then
        print_success "SSH configuration is valid"
        changes_applied=true
    else
        print_error "SSH configuration test FAILED!"
        print_warning "Reverting changes to prevent lockout..."

        # Restore from backup
        local backup_file=$(ls -t "${sshd_config}.backup."* 2>/dev/null | head -1)
        if [[ -n "${backup_file}" ]]; then
            cp "${backup_file}" "${sshd_config}"
            print_success "Configuration reverted to backup"
        fi

        print_error "SSH security changes were NOT applied due to configuration error"
        return 1
    fi

    # Disable SSH socket activation (Ubuntu 24.04+ uses this by default)
    print_info "Disabling SSH socket activation to allow custom port..."
    systemctl disable ssh.socket &>/dev/null || true
    systemctl stop ssh.socket &>/dev/null || true
    systemctl enable ssh.service &>/dev/null || true
    print_success "SSH socket activation disabled"

    # Restart SSH service
    print_info "Restarting SSH service on port ${SSH_PORT}..."
    if systemctl restart ssh.service 2>/dev/null; then
        print_success "SSH service restarted successfully"
    else
        print_error "Failed to restart SSH service"
        print_warning "SSH may not be accessible until service is restarted"
        return 1
    fi

    # Wait for SSH to fully restart
    sleep 2

    # Verify SSH is listening on correct port
    print_info "Verifying SSH is listening on port ${SSH_PORT}..."
    if ss -tlnp | grep -q ":${SSH_PORT}.*sshd"; then
        print_success "SSH is now listening on port ${SSH_PORT}"
    else
        print_warning "SSH may not be listening on port ${SSH_PORT} yet"
        print_info "Check with: ss -tlnp | grep sshd"
    fi

    # Update UFW firewall - remove port 22, keep port 2222
    print_info "Updating firewall rules..."
    print_info "Removing temporary SSH port 22 from firewall..."

    # Delete the temporary port 22 rule
    ufw delete allow 22/tcp &>/dev/null || true
    print_success "Port 22 closed on firewall"
    print_success "Port ${SSH_PORT} remains open for SSH/SCP"

    # Reload firewall
    ufw reload &>/dev/null
    print_success "Firewall updated"

    # Update fail2ban if it's running
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        print_info "Updating fail2ban configuration for new SSH port..."
        local jail_local="/etc/fail2ban/jail.local"

        if [[ -f "${jail_local}" ]]; then
            sed -i "s/^port = .*/port = ${SSH_PORT}/" "${jail_local}"
            systemctl restart fail2ban &>/dev/null
            print_success "Fail2ban updated for port ${SSH_PORT}"
        fi
    fi

    echo ""
    print_color "${GREEN}" "================================================================================"
    print_color "${GREEN}" "               SSH Security Hardening Applied Successfully!"
    print_color "${GREEN}" "================================================================================"
    echo ""

    print_color "${YELLOW}" "Changes Applied:"
    echo "  - Password authentication: DISABLED (SSH keys only)"
    echo "  - Root login via SSH: DISABLED"
    echo "  - SSH port changed: 22 -> ${SSH_PORT}"
    echo "  - Firewall updated: Port 22 CLOSED, Port ${SSH_PORT} OPEN"
    echo ""

    print_color "${RED}" "CRITICAL - TEST SSH ACCESS NOW!"
    echo ""
    print_color "${YELLOW}" "Do NOT close this terminal session until you verify SSH access works!"
    echo ""
    print_color "${CYAN}" "1. Open a NEW terminal window"
    echo ""
    print_color "${CYAN}" "2. Test the new SSH connection:"
    print_color "${GREEN}" "   ssh -p ${SSH_PORT} ${USERNAME}@your-server-ip"
    echo ""
    print_color "${CYAN}" "3. If you can connect successfully, the setup is complete"
    echo ""
    print_color "${CYAN}" "4. Only after verifying SSH works, close this terminal"
    echo ""

    print_color "${RED}" "If you CANNOT connect:"
    echo ""
    print_color "${YELLOW}" "   - Keep this terminal session open"
    print_color "${YELLOW}" "   - Revert changes by restoring backup:"
    print_color "${CYAN}" "     sudo cp ${sshd_config}.backup.* ${sshd_config}"
    print_color "${CYAN}" "     sudo systemctl restart sshd"
    print_color "${CYAN}" "     sudo ufw allow 22/tcp"
    print_color "${CYAN}" "     sudo ufw delete allow ${SSH_PORT}/tcp"
    print_color "${CYAN}" "     sudo ufw reload"
    echo ""

    print_color "${GREEN}" "================================================================================"
    echo ""

    print_success "SSH security hardening completed"
}

################################################################################
# STEP 17: FINAL STEPS
################################################################################

display_summary() {
    print_step "17" "Installation Summary"

    print_color "${GREEN}" "================================================================================"
    print_color "${GREEN}" "                    Installation Summary"
    print_color "${GREEN}" "================================================================================"
    echo ""

    print_color "${CYAN}" "SYSTEM INFORMATION:"
    echo "  Hostname: $(hostname)"
    echo "  Timezone: $(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone)"
    echo "  Locale: ${LOCALE}"
    echo ""

    print_color "${CYAN}" "INSTALLED SOFTWARE VERSIONS:"
    show_version "  Node.js" "node --version 2>/dev/null || echo 'not installed'"
    show_version "  npm" "npm --version 2>/dev/null || echo 'not installed'"
    show_version "  Yarn" "yarn --version 2>/dev/null || echo 'not installed'"
    show_version "  Ruby" "sudo -u ${USERNAME} bash -c 'source ${USER_HOME}/.bashrc && ruby --version' 2>/dev/null || echo 'not installed'"
    show_version "  Rails" "sudo -u ${USERNAME} bash -c 'source ${USER_HOME}/.bashrc && rails --version' 2>/dev/null || echo 'not installed'"
    show_version "  PostgreSQL" "psql --version 2>/dev/null || echo 'not installed'"
    show_version "  Redis" "redis-server --version 2>/dev/null || echo 'not installed'"
    show_version "  Docker" "docker --version 2>/dev/null || echo 'not installed'"
    show_version "  Docker Compose" "docker compose version 2>/dev/null || echo 'not installed'"
    show_version "  Nginx" "nginx -v 2>&1 | head -1 || echo 'not installed'"
    show_version "  Git" "git --version 2>/dev/null || echo 'not installed'"
    echo ""

    print_color "${CYAN}" "SECURITY CONFIGURATION:"

    # Check if SSH hardening was applied
    local ssh_hardened=false
    if grep -q "^Port ${SSH_PORT}" /etc/ssh/sshd_config 2>/dev/null && \
       grep -q "^PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null; then
        ssh_hardened=true
    fi

    if [[ "${ssh_hardened}" == "true" ]]; then
        echo "  SSH Port: ${SSH_PORT} (hardened)"
        echo "  Password Authentication: DISABLED (SSH keys only)"
        echo "  Root Login: DISABLED"
    else
        echo "  SSH Port: 22 (default - hardening not applied)"
        if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; then
            echo "  Password Authentication: DISABLED"
        else
            echo "  Password Authentication: enabled"
        fi
        if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null; then
            echo "  Root Login: DISABLED"
        else
            echo "  Root Login: enabled"
        fi
    fi

    if systemctl is-active --quiet ufw; then
        echo "  UFW Firewall: ENABLED"
    else
        echo "  UFW Firewall: disabled"
    fi

    if systemctl is-active --quiet fail2ban; then
        if [[ "${ssh_hardened}" == "true" ]]; then
            echo "  Fail2ban: ENABLED (monitoring port ${SSH_PORT})"
        else
            echo "  Fail2ban: ENABLED"
        fi
    else
        echo "  Fail2ban: disabled"
    fi
    echo ""

    print_color "${CYAN}" "USER CONFIGURATION:"
    echo "  User: ${USERNAME}"
    if groups "${USERNAME}" 2>/dev/null | grep -q '\bsudo\b'; then
        echo "  Sudo Access: YES"
    else
        echo "  Sudo Access: NO"
    fi

    if [[ -f "${USER_SSH_DIR}/authorized_keys" ]]; then
        echo "  SSH Keys: Configured"
    else
        echo "  SSH Keys: Not configured"
    fi
    echo ""

    print_color "${CYAN}" "SERVICES STATUS:"
    local services=("ssh" "cron" "postgresql" "redis-server" "docker" "nginx")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "${service}" 2>/dev/null; then
            echo "  ${service}: RUNNING"
        fi
    done
    echo ""

    # SSL Certificate Information
    if [[ -f /etc/letsencrypt/live/webet.pl/fullchain.pem ]]; then
        print_color "${CYAN}" "SSL CERTIFICATE:"
        echo "  Domain: webet.pl, www.webet.pl"

        local expiry_date
        expiry_date=$(openssl x509 -in /etc/letsencrypt/live/webet.pl/fullchain.pem -noout -enddate 2>/dev/null | cut -d= -f2)
        echo "  Expires: ${expiry_date}"

        if systemctl is-active --quiet certbot.timer 2>/dev/null; then
            echo "  Auto-Renewal: ENABLED"
        else
            echo "  Auto-Renewal: disabled"
        fi

        echo "  URLs:"
        echo "    https://webet.pl"
        echo "    https://www.webet.pl"
        echo ""
    fi

    print_color "${GREEN}" "================================================================================"
    echo ""
}

display_next_steps() {
    print_color "${YELLOW}" "================================================================================"
    print_color "${YELLOW}" "                         IMPORTANT INFORMATION"
    print_color "${YELLOW}" "================================================================================"
    echo ""

    # Check if SSH hardening was applied
    local ssh_hardened=false
    if grep -q "^Port ${SSH_PORT}" /etc/ssh/sshd_config 2>/dev/null && \
       grep -q "^PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null; then
        ssh_hardened=true
    fi

    if [[ "${ssh_hardened}" == "true" ]]; then
        print_color "${RED}" "SSH SECURITY HARDENING APPLIED:"
        echo ""
        print_color "${YELLOW}" "  - SSH is now running on port ${SSH_PORT}"
        print_color "${YELLOW}" "  - Password authentication is DISABLED (SSH keys only)"
        print_color "${YELLOW}" "  - Root login is DISABLED"
        print_color "${YELLOW}" "  - Port 22 is CLOSED on firewall"
        echo ""
        print_color "${CYAN}" "  New SSH connection command:"
        print_color "${GREEN}" "    ssh -p ${SSH_PORT} ${USERNAME}@your-server-ip"
        echo ""
        print_color "${RED}" "  CRITICAL: Verify SSH access in a new terminal before closing this session!"
        echo ""
    else
        print_color "${YELLOW}" "SSH SECURITY NOT APPLIED:"
        echo ""
        print_color "${CYAN}" "  Current SSH connection (unchanged):"
        print_color "${GREEN}" "    ssh root@your-server-ip"
        echo ""
        print_info "SSH hardening was skipped. You can apply it manually later if needed."
        echo ""
    fi

    print_color "${YELLOW}" "NEXT STEPS:"
    echo ""

    if [[ "${ssh_hardened}" == "true" ]]; then
        echo "  1. TEST SSH connection in a NEW terminal window (CRITICAL):"
        print_color "${CYAN}" "     ssh -p ${SSH_PORT} ${USERNAME}@your-server-ip"
        echo ""
        echo "  2. Only close this terminal after verifying SSH works"
        echo ""
        echo "  3. For Ruby/Rails to work, user ${USERNAME} needs to login or run:"
        print_color "${CYAN}" "     source ~/.bashrc"
        echo ""
        echo "  4. For Docker to work without sudo, user ${USERNAME} needs to log out and back in"
        echo ""
        echo "  5. If you generated a GitHub SSH key, add it to GitHub:"
        print_color "${CYAN}" "     https://github.com/settings/keys"
        echo ""
    else
        echo "  1. For Ruby/Rails to work, user ${USERNAME} needs to login or run:"
        print_color "${CYAN}" "     source ~/.bashrc"
        echo ""
        echo "  2. For Docker to work without sudo, user ${USERNAME} needs to log out and back in"
        echo ""
        echo "  3. If you generated a GitHub SSH key, add it to GitHub:"
        print_color "${CYAN}" "     https://github.com/settings/keys"
        echo ""
        echo "  4. Consider applying SSH hardening for better security"
        echo ""
    fi

    if [[ -f /etc/letsencrypt/live/webet.pl/fullchain.pem ]]; then
        local step_num
        if [[ "${ssh_hardened}" == "true" ]]; then
            step_num="6"
        else
            step_num="5"
        fi

        echo "  ${step_num}. Your SSL certificate is configured and active:"
        print_color "${GREEN}" "     https://webet.pl"
        print_color "${GREEN}" "     https://www.webet.pl"
        echo ""
        ((step_num++))
        echo "  ${step_num}. HTTP traffic automatically redirects to HTTPS (HTTPS-only mode)"
        echo ""
        ((step_num++))
        echo "  ${step_num}. SSL certificate auto-renewal is enabled (checks twice daily)"
        echo ""
        ((step_num++))
        echo "  ${step_num}. To manually renew the certificate (if needed):"
        print_color "${CYAN}" "     sudo certbot renew"
        echo ""
        ((step_num++))
        echo "  ${step_num}. Review the installation log:"
        print_color "${CYAN}" "     cat ${LOG_FILE}"
        echo ""
    else
        local step_num
        if [[ "${ssh_hardened}" == "true" ]]; then
            step_num="6"
        else
            step_num="5"
        fi

        echo "  ${step_num}. Site is currently HTTP-only (accessible at http://webet.pl)"
        echo ""
        ((step_num++))
        echo "  ${step_num}. To set up SSL and enable HTTPS for webet.pl:"
        print_color "${CYAN}" "     sudo certbot --nginx -d webet.pl -d www.webet.pl --email admin@webet.pl"
        echo ""
        ((step_num++))
        echo "  ${step_num}. After running certbot, HTTP will automatically redirect to HTTPS"
        echo ""
        ((step_num++))
        echo "  ${step_num}. Review the installation log:"
        print_color "${CYAN}" "     cat ${LOG_FILE}"
        echo ""
    fi

    print_color "${YELLOW}" "================================================================================"
    echo ""

    print_color "${GREEN}" "Server initialization completed successfully!"
    echo ""
}

################################################################################
# MAIN FUNCTION
################################################################################

main() {
    clear

    print_color "${BLUE}" "================================================================================"
    print_color "${BLUE}" "           Ubuntu Server Initialization Script v${SCRIPT_VERSION}"
    print_color "${BLUE}" "================================================================================"
    print_color "${BLUE}" "  General-purpose server setup for Node.js and Rails applications"
    print_color "${BLUE}" "================================================================================"
    echo ""

    # Initialize logging
    init_log

    # Check prerequisites
    check_root

    # Confirm before proceeding
    print_warning "This script will make significant changes to your system."
    if ! ask_yes_no "Do you want to continue?" "y"; then
        print_info "Installation cancelled by user"
        exit 0
    fi

    echo ""

    # Execute installation steps
    update_system
    set_timezone
    configure_locale

    if ask_yes_no "Setup user '${USERNAME}' with sudo privileges?" "y"; then
        setup_user
    fi

    if ask_yes_no "Set hostname to '${NEW_HOSTNAME}'?" "y"; then
        setup_hostname
    fi

    # Setup firewall early (but keep port 22 open until SSH hardening at the end)
    setup_firewall

    if ask_yes_no "Install and configure fail2ban?" "y"; then
        setup_fail2ban
    fi

    install_essential_tools

    if ask_yes_no "Install fzf (fuzzy finder with CTRL+P)?" "y"; then
        install_fzf
    fi

    if ask_yes_no "Install Node.js ${NODE_VERSION}.x?" "y"; then
        install_nodejs
    fi

    if ask_yes_no "Install Ruby ${RUBY_VERSION} and Rails?" "y"; then
        install_rbenv
    fi

    if ask_yes_no "Install PostgreSQL and Redis?" "y"; then
        install_databases
    fi

    if ask_yes_no "Install Docker?" "y"; then
        install_docker
    fi

    if ask_yes_no "Install Nginx web server?" "y"; then
        install_nginx
        setup_letsencrypt
    fi

    if ask_yes_no "Install Rails development libraries?" "y"; then
        install_rails_libraries
    fi

    setup_github_ssh

    if ask_yes_no "Optimize system (swap, limits, auto-updates)?" "y"; then
        system_optimization
    fi

    setup_cron

    # FINAL STEP: Apply SSH security hardening
    # This is done at the end to prevent lockout if earlier steps fail
    echo ""
    apply_ssh_security

    # Display summary and next steps
    echo ""
    display_summary
    display_next_steps

    log_message "INFO" "=== Server Initialization Completed at $(date) ==="

    print_color "${GREEN}" "Installation log saved to: ${LOG_FILE}"
    echo ""
}

################################################################################
# ERROR HANDLING
################################################################################

# Trap errors
trap 'error_exit "Script failed at line $LINENO. Check ${LOG_FILE} for details."' ERR

################################################################################
# SCRIPT ENTRY POINT
################################################################################

main "$@"

exit 0
