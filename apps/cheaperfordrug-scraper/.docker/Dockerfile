# Multi-stage Dockerfile for CheaperForDrug Scraper with NordVPN
# Base: Ubuntu 24.04 with Node.js 20, NordVPN CLI, and Playwright
# Supports country-specific scraping with VPN protection

# ============================================================================
# Stage 1: Base Image with System Dependencies
# ============================================================================
FROM ubuntu:24.04 AS base

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Set timezone
ENV TZ=Europe/Warsaw

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # Core utilities
    curl \
    wget \
    gnupg2 \
    ca-certificates \
    apt-transport-https \
    software-properties-common \
    # Network utilities
    iputils-ping \
    net-tools \
    dnsutils \
    # VPN dependencies
    iptables \
    iproute2 \
    # Cron for VPN rotation
    cron \
    # Process management
    supervisor \
    # Debugging tools
    vim \
    less \
    procps \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Stage 2: Node.js Installation
# ============================================================================
FROM base AS nodejs

# Install Node.js 20.x LTS
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g npm@latest \
    && rm -rf /var/lib/apt/lists/*

# Verify Node.js installation
RUN node --version && npm --version

# ============================================================================
# Stage 3: NordVPN Installation
# ============================================================================
FROM nodejs AS nordvpn

# Download and install NordVPN
# Note: Using Ubuntu 22.04 (jammy) repository as Ubuntu 24.04 may not be fully supported yet
RUN sh -c 'curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh | sh' \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create nordvpn group and set up permissions
RUN groupadd -g 1001 nordvpn || true \
    && usermod -aG nordvpn root

# ============================================================================
# Stage 4: Application Setup
# ============================================================================
FROM nordvpn AS app

# Create application user and directories
RUN useradd -m -u 1000 -s /bin/bash scraper \
    && mkdir -p /app /app/logs /app/outputs /app/state \
    && chown -R scraper:scraper /app

# Set working directory
WORKDIR /app

# Copy package files first (for layer caching)
COPY --chown=scraper:scraper package*.json ./

# Install Node.js dependencies as scraper user
USER scraper
RUN npm ci --only=production \
    && npx playwright install --with-deps chromium

# Switch back to root for system-level operations
USER root

# Install Playwright system dependencies that might be missing
RUN npx playwright install-deps chromium

# Copy application code
COPY --chown=scraper:scraper . .

# Copy Docker-specific scripts (these are copied to repo root by setup.sh)
COPY --chown=root:root entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=root:root vpn-rotate.sh /usr/local/bin/vpn-rotate.sh
COPY --chown=root:root run-scraper.sh /usr/local/bin/run-scraper.sh
COPY --chown=root:root run-scraper-cron.sh /usr/local/bin/run-scraper-cron.sh
COPY --chown=root:root send-scraper-email-wrapper.sh /usr/local/bin/send-scraper-email-wrapper.sh
COPY --chown=root:root healthcheck.sh /usr/local/bin/healthcheck.sh
COPY --chown=root:root supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy container-level cron configuration
COPY --chown=root:root container-cron /etc/cron.d/scraper-cron

# Make scripts executable
RUN chmod +x /usr/local/bin/entrypoint.sh \
    /usr/local/bin/vpn-rotate.sh \
    /usr/local/bin/run-scraper.sh \
    /usr/local/bin/run-scraper-cron.sh \
    /usr/local/bin/send-scraper-email-wrapper.sh \
    /usr/local/bin/healthcheck.sh

# Setup cron
RUN chmod 0644 /etc/cron.d/scraper-cron \
    && crontab /etc/cron.d/scraper-cron \
    && touch /var/log/cron.log

# Create log directories for supervisor and cron
RUN mkdir -p /var/log/supervisor /app/logs/cron \
    && chown -R scraper:scraper /var/log/supervisor /app/logs/cron

# Environment variables (can be overridden at runtime)
ENV NODE_ENV=production \
    HEADLESS=true \
    SEND_TO_API=true \
    VPN_ROTATE_INTERVAL=15

# Expose ports (if needed for health checks)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=60s --timeout=10s --start-period=120s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

# NOTE: No VOLUME declaration here!
# Volume mounts are defined in docker-compose.yml as bind mounts from host.
# A VOLUME declaration here would create anonymous Docker volumes that override
# the bind mounts, storing data inside Docker's volume system instead of on the host.
# This would break the stateless container architecture and cause data loss on container deletion.
#
# Volume mounts are configured in docker-compose.yml:
#   - ${APP_DIR}/logs/{country}:/app/logs
#   - ${APP_DIR}/outputs/{country}:/app/outputs
#   - ${APP_DIR}/state/{country}:/app/state

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Default command (can be overridden)
CMD ["scraper"]
